"""Delivery reconciliation for ``backlog finish`` and ``sync``."""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from .commands import ClerkExit, _emit_stderr, _git, _primary_repo_root, _show_ref, _success, backend_fail, usage
from .proc import CommandRunner
from .work_graph import BdWorkGraphAdapter, Work, WorkGraphBackendError

RECONCILIATION_VERBS = frozenset({("sync",), ("backlog", "finish")})


def _short(id_: str) -> str:
    value = id_[1:] if id_.startswith("#") else id_
    return value.split("-", 1)[1] if "-" in value else value


def _current_delivery_short(runner: CommandRunner, root: Path) -> str:
    branch = _git(runner, root, ["symbolic-ref", "--quiet", "--short", "HEAD"]).stdout.strip()
    return branch.removeprefix("delivery/") if branch.startswith("delivery/") else ""


def _resolve_work(backend: str, runner: CommandRunner, root: Path, id_arg: str) -> tuple[str, str] | None:
    if backend == "bd":
        try:
            work = BdWorkGraphAdapter(runner).find(id_arg)
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"finish failed — could not resolve Work {id_arg}: {exc}")
        return (work.id, _short(work.id)) if work is not None else None
    if backend == "gh":
        result = runner.run(["gh", "issue", "view", id_arg, "--json", "number,title,body,assignees,state"])
        if result.returncode != 0:
            return None
        try:
            value = json.loads(result.stdout)
        except json.JSONDecodeError:
            backend_fail(f"finish failed — gh issue view did not return valid JSON for {id_arg}")
        if not isinstance(value, dict) or not value.get("number"):
            return None
        full = str(value["number"])
        return full, full
    backend_fail(f"finish failed — unsupported backend {backend}")
    raise AssertionError("unreachable")


def _active_pr(runner: CommandRunner, branch: str) -> dict[str, Any] | None:
    result = runner.run(
        [
            "gh", "pr", "list", "--head", branch, "--state", "all", "--json",
            "number,url,state,mergedAt,reviewDecision,statusCheckRollup,headRefName,isDraft,updatedAt",
        ]
    )
    if result.returncode != 0:
        backend_fail(f"finish failed — gh pr list did not succeed for {branch}")
    try:
        values = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        backend_fail(f"finish failed — gh pr list did not return valid JSON for {branch}")
    if not isinstance(values, list) or any(not isinstance(value, dict) for value in values):
        backend_fail(f"finish failed — gh pr list did not return a PR list for {branch}")
    open_prs = sorted((value for value in values if value.get("state") == "OPEN"), key=lambda value: str(value.get("updatedAt") or ""), reverse=True)
    merged_prs = sorted(
        (value for value in values if value.get("state") == "MERGED" or value.get("mergedAt")),
        key=lambda value: str(value.get("updatedAt") or ""),
        reverse=True,
    )
    return (open_prs or merged_prs or [None])[0]


def _check_names(pr: Mapping[str, Any], kind: str) -> tuple[str, ...]:
    names: list[str] = []
    for check in pr.get("statusCheckRollup") or []:
        if not isinstance(check, dict):
            continue
        conclusion = str(check.get("conclusion") or "").upper()
        status = str(check.get("status") or "").upper()
        failed = conclusion in {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED"} or (
            status == "COMPLETED" and conclusion not in {"", "SUCCESS", "SKIPPED", "NEUTRAL"}
        )
        pending = not conclusion and status != "COMPLETED"
        if (kind == "failed" and failed) or (kind == "pending" and pending):
            names.append(str(check.get("name") or check.get("context") or check.get("workflowName") or "unnamed check"))
    return tuple(names)


def _push_if_needed(runner: CommandRunner, root: Path, short: str) -> int:
    branch = f"delivery/{short}"
    if not _show_ref(runner, root, f"refs/heads/{branch}") or _show_ref(runner, root, f"refs/remotes/origin/{branch}"):
        return 0
    _git(runner, root, ["fetch", "origin", "main"])
    base = _git(runner, root, ["rev-parse", "origin/main"])
    merge_base = _git(runner, root, ["merge-base", branch, "origin/main"])
    if base.returncode == 0 and merge_base.returncode == 0 and merge_base.stdout.strip() != base.stdout.strip():
        print(f"clerk: backlog finish refused — delivery/{short} is behind origin/main", file=sys.stderr)
        print("       run 'git rebase origin/main', then rerun 'clerk backlog finish'", file=sys.stderr)
        return 2
    if _git(runner, root, ["push", "-u", "origin", branch]).returncode != 0:
        backend_fail(f"finish failed — could not push {branch} to origin")
    _git(runner, root, ["fetch", "origin"])
    return 0


def _remote_branch_exists(runner: CommandRunner, root: Path, branch: str) -> bool:
    return _git(runner, root, ["ls-remote", "--exit-code", "--heads", "origin", branch]).returncode == 0


def _cleanup_merged(
    backend: str,
    runner: CommandRunner,
    root: Path,
    full: str,
    short: str,
    pr_number: str,
    env: Mapping[str, str],
) -> None:
    main_root = _primary_repo_root(runner, root)
    try:
        os.chdir(main_root)
    except OSError:
        backend_fail(f"finish failed — could not cd to {main_root} before cleanup")
    worktree = main_root / ".worktrees" / short
    if worktree.is_dir():
        if _git(runner, main_root, ["worktree", "remove", str(worktree)]).returncode != 0:
            backend_fail(f"finish failed — could not remove the worktree at {worktree} (commit or stash local changes first)")
    else:
        _git(runner, main_root, ["worktree", "prune"])
    branch = f"delivery/{short}"
    if _show_ref(runner, main_root, f"refs/heads/{branch}") and _git(runner, main_root, ["branch", "-D", branch]).returncode != 0:
        backend_fail(f"finish failed — could not delete local branch {branch}")
    if _remote_branch_exists(runner, main_root, branch):
        if _git(runner, main_root, ["push", "origin", "--delete", branch]).returncode != 0:
            backend_fail(f"finish failed — could not delete origin {branch}")
        if _remote_branch_exists(runner, main_root, branch):
            backend_fail(f"finish failed — origin still advertises {branch} after deletion")
    if backend == "bd":
        try:
            BdWorkGraphAdapter(runner).finish_delivery(full, f"delivered: PR #{pr_number} merged")
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"finish failed — {exc}")
    else:
        runner.run(["gh", "issue", "edit", full, "--remove-label", "ready-for-agent"])
    _success(f"finished {full} — PR #{pr_number} merged, delivery/{short} cleaned up, unit closed", env)


def _reconcile(
    backend: str,
    runner: CommandRunner,
    root: Path,
    id_arg: str,
    watch: bool,
    sync: bool,
    env: Mapping[str, str],
) -> int:
    inferred_short = ""
    if not id_arg:
        inferred_short = _current_delivery_short(runner, root)
        id_arg = inferred_short
    resolved = _resolve_work(backend, runner, root, id_arg) if id_arg else None
    if resolved is None:
        if sync:
            print(f"clerk: sync: skipped an unresolvable claim id {id_arg or '<current>'}")
            return 0
        if inferred_short and backend == "bd":
            print(
                f"clerk: could not resolve bead for delivery/{inferred_short} — run 'bd dolt pull' to refresh local state or rerun 'clerk backlog finish <full-id>'",
                file=sys.stderr,
            )
        usage("clerk backlog finish: not inside delivery/<short> and no id was supplied — cd into the claimed worktree or run 'clerk backlog finish <id>'")
    full, short = resolved
    branch = f"delivery/{short}"
    push_code = _push_if_needed(runner, root, short)
    if push_code:
        return push_code
    pr = _active_pr(runner, branch)
    if pr is None:
        if sync:
            if not _show_ref(runner, root, f"refs/heads/{branch}") and not _show_ref(runner, root, f"refs/remotes/origin/{branch}"):
                print(f"clerk: sync: {full} is claimed but has no delivery/{short} branch/worktree — no PR created")
            else:
                print(f"clerk: sync: {full} has delivery/{short} but no PR — no PR created; run 'clerk backlog submit {full} --body-file <path-to-pr-body.md>'")
            return 0
        print(f"clerk: backlog finish refused — no PR found for delivery/{short}", file=sys.stderr)
        print(f"       run 'clerk backlog submit {full} --body-file <path-to-pr-body.md>'", file=sys.stderr)
        return 2
    pr_number = str(pr.get("number") or "")
    if pr.get("state") == "MERGED" or pr.get("mergedAt"):
        _cleanup_merged(backend, runner, root, full, short, pr_number, env)
        return 0
    if watch:
        result = runner.run(["gh", "pr", "checks", pr_number, "--watch"])
        if result.returncode != 0:
            backend_fail(f"finish failed — gh pr checks --watch failed for PR #{pr_number}")
        pr = _active_pr(runner, branch)
        if pr is None:
            backend_fail(f"finish failed — PR #{pr_number} disappeared after gh pr checks --watch")
    failures = _check_names(pr, "failed")
    if failures:
        print(f"clerk: PR #{pr_number} for {full} has failing checks")
        for name in failures:
            print(f"  {name}")
        return 1
    pending = _check_names(pr, "pending")
    if pending:
        print(f"clerk: PR #{pr_number} for {full} has pending checks — run 'clerk backlog finish {full} --watch' to wait")
        for name in pending:
            print(f"  {name}")
        return 0
    if pr.get("reviewDecision") in {"REVIEW_REQUIRED", "CHANGES_REQUESTED"}:
        print(f"clerk: PR #{pr_number} for {full} is awaiting review — finish will complete after review")
        return 0
    if runner.run(["gh", "pr", "merge", pr_number, "--squash", "--delete-branch=false"]).returncode != 0:
        backend_fail(f"finish failed — gh pr merge --squash did not succeed for PR #{pr_number}")
    pr = _active_pr(runner, branch)
    if pr is None or (pr.get("state") != "MERGED" and not pr.get("mergedAt")):
        backend_fail(f"finish failed — PR #{pr_number} was not confirmed merged after gh pr merge")
    _cleanup_merged(backend, runner, root, full, short, pr_number, env)
    return 0


def cmd_backlog_finish(
    backend: str,
    root: Path,
    argv: Sequence[str],
    runner: CommandRunner,
    env: Mapping[str, str],
) -> int:
    watch = False
    id_arg = ""
    for arg in argv:
        if arg == "--watch":
            watch = True
        elif id_arg:
            usage(f"clerk backlog finish: unknown argument '{arg}' — usage: clerk backlog finish [<id>] [--watch]")
        else:
            id_arg = arg
    return _reconcile(backend, runner, root, id_arg, watch, False, env)


def cmd_sync(
    backend: str,
    root: Path,
    argv: Sequence[str],
    runner: CommandRunner,
    env: Mapping[str, str],
) -> int:
    if argv:
        usage(f"clerk sync: unknown argument '{argv[0]}' — usage: clerk sync")
    if backend == "gh":
        print("clerk: sync: gh-backed claim sweep is not available in this generation; skipping", file=sys.stderr)
        return 0
    if backend != "bd":
        backend_fail(f"sync failed — unsupported backend {backend}")
    try:
        claims = BdWorkGraphAdapter(runner).open_claims()
    except WorkGraphBackendError as exc:
        _emit_stderr(exc.result)
        backend_fail("sync failed — bd list did not succeed")
    print(f"clerk: sync scanning {len(claims)} open claim(s)")
    for work in claims:
        _reconcile(backend, runner, root, work.id, False, True, env)
    return 0


_HANDLERS = {("sync",): cmd_sync, ("backlog", "finish"): cmd_backlog_finish}


def run_reconciliation(
    path: tuple[str, ...],
    backend: str,
    root: Path,
    argv: Sequence[str],
    env: Mapping[str, str] = os.environ,
    runner: CommandRunner | None = None,
) -> int:
    try:
        return _HANDLERS[path](backend, root, argv, runner or CommandRunner(), env)
    except ClerkExit as exc:
        return exc.code
