"""Project-gate protocol and trusted-default adapter execution."""

from __future__ import annotations

import json
import os
import re
import stat
import sys
import tempfile
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from .commands import ClerkExit, _emit_stderr, _git, _success, backend_fail, usage
from .manifest import ManifestStatus, parse_manifest
from .proc import CommandResult, CommandRunner
from .work_graph import BdWorkGraphAdapter, WorkGraphBackendError, acceptance_criteria


_PR_URL = re.compile(
    r"https://github\.com/"
    r"[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}/"
    r"(?=[A-Za-z0-9._-]{1,100}/pull/)(?=[^/]*[A-Za-z0-9])[A-Za-z0-9._-]+/"
    r"pull/[1-9][0-9]*\n?"
)


@dataclass(frozen=True)
class GateConfig:
    adapter: str
    submission_owner: str
    trusted_ref: str


@dataclass(frozen=True)
class GateResult:
    status: str
    summary: str
    assessed_commit: str
    run_id: str | None
    delivery_completed: bool


def _safe_repo_path(value: object) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path == PurePosixPath("."):
        return None
    return str(path)


def _trusted_ref(runner: CommandRunner, root: Path) -> str:
    result = _git(runner, root, ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
    candidate = result.stdout.strip()
    if candidate and _git(runner, root, ["rev-parse", "--verify", "--quiet", candidate]).returncode == 0:
        return candidate
    for candidate in ("origin/main", "main"):
        if _git(runner, root, ["rev-parse", "--verify", "--quiet", candidate]).returncode == 0:
            return candidate
    backend_fail("project gate failed — could not resolve the trusted default branch")
    raise AssertionError("unreachable")


def _trusted_file(runner: CommandRunner, root: Path, ref: str, path: str, message: str) -> str:
    result = _git(runner, root, ["show", f"{ref}:{path}"])
    if result.returncode != 0:
        backend_fail(message)
    return result.stdout


def _load_config(runner: CommandRunner, root: Path) -> GateConfig:
    ref = _trusted_ref(runner, root)
    manifest = parse_manifest(
        _trusted_file(runner, root, ref, ".clerk", "project gate failed — trusted .clerk is missing or unreadable"),
        root / ".clerk",
    )
    if manifest.status is not ManifestStatus.OK or not manifest.project_gate:
        backend_fail("project gate failed — trusted .clerk has no project-gate configuration")
    config_path = _safe_repo_path(manifest.project_gate)
    if config_path is None:
        backend_fail("project gate failed — trusted .clerk project-gate configuration is outside the repository")
    raw = _trusted_file(
        runner,
        root,
        ref,
        config_path,
        "project gate failed — trusted project-gate configuration is missing or unreadable",
    )
    try:
        config = json.loads(raw)
    except json.JSONDecodeError:
        backend_fail("project gate failed — trusted project-gate configuration is malformed")
    if not isinstance(config, dict):
        backend_fail("project gate failed — trusted project-gate configuration is malformed")
    adapter = _safe_repo_path(config.get("adapter"))
    owner = config.get("submission_owner", "clerk")
    if adapter is None or owner not in {"clerk", "project-gate"}:
        backend_fail("project gate failed — trusted project-gate configuration is malformed")
    # Read it now, while ref is fixed, so a delivery branch can never supply the executable.
    _trusted_file(runner, root, ref, adapter, "project gate failed — trusted project-gate adapter is missing or unreadable")
    return GateConfig(adapter=adapter, submission_owner=owner, trusted_ref=ref)


def _adapter_source(runner: CommandRunner, root: Path, config: GateConfig) -> str:
    return _trusted_file(
        runner,
        root,
        config.trusted_ref,
        config.adapter,
        "project gate failed — trusted project-gate adapter is missing or unreadable",
    )


def _work(backend: str, runner: CommandRunner, id_: str, verb: str) -> tuple[str, str, str]:
    if backend == "bd":
        try:
            work = BdWorkGraphAdapter(runner).find(id_)
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"{verb.removeprefix('clerk ')} Work lookup failed — {exc}")
        if work is None:
            usage(f"{verb}: {id_} not found — check the id ('clerk backlog next' shows ready units)")
        return work.id, work.title, work.acceptance_criteria
    result = runner.run(["gh", "issue", "view", id_, "--json", "number,title,body"])
    if result.returncode != 0:
        usage(f"{verb}: {id_} not found — check the id ('clerk backlog next' shows ready units)")
    try:
        obj = json.loads(result.stdout)
    except json.JSONDecodeError:
        backend_fail(f"{verb.removeprefix('clerk ')} failed — gh issue view did not return valid JSON")
    if not isinstance(obj, dict):
        backend_fail(f"{verb.removeprefix('clerk ')} failed — gh issue view did not return an issue object")
    return f"#{obj.get('number')}", str(obj.get("title") or ""), acceptance_criteria({"description": obj.get("body")})


def _proof_criteria(acceptance: str) -> list[str]:
    bullets: list[str] = []
    fallback: list[str] = []
    for line in acceptance.splitlines():
        text = line.strip()
        if not text or re.fullmatch(r"#{0,6}\s*acceptance criteria:?", text, re.IGNORECASE):
            continue
        bullet = re.fullmatch(r"(?:-|\d+[.)])\s+(.+?)\s*", text)
        if bullet:
            bullets.append(bullet.group(1).strip())
        else:
            fallback.append(text)
    return bullets if bullets or len(fallback) != 1 else fallback


def cmd_backlog_proof(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner) -> int:
    if not argv:
        usage("clerk backlog proof: missing id — usage: clerk backlog proof <id>")
    if len(argv) > 1:
        usage(f"clerk backlog proof: unknown argument '{argv[1]}' — usage: clerk backlog proof <id>")
    work_id, _, acceptance = _work(backend, runner, argv[0], "clerk backlog proof")
    criteria = _proof_criteria(acceptance)
    if not criteria:
        usage(f"clerk backlog proof: {work_id} has no acceptance criteria — return it to discovery before submitting")
    print(json.dumps({"acceptance": [{"text": text, "evidence": ""} for text in criteria]}, indent=2, ensure_ascii=False))
    return 0


def _short(id_: str) -> str:
    value = id_[1:] if id_.startswith("#") else id_
    return value.split("-", 1)[1] if "-" in value else value


def _current_branch(runner: CommandRunner, root: Path) -> str:
    return _git(runner, root, ["symbolic-ref", "--quiet", "--short", "HEAD"]).stdout.strip()


def _request(work_id: str, title: str, acceptance: str, branch: str, root: Path, owner: str, run_id: str | None = None) -> dict[str, Any]:
    request: dict[str, Any] = {
        "work": {"id": work_id, "title": title, "acceptance_criteria": acceptance},
        "delivery": {"branch": branch, "starting_commit": "", "worktree": str(root)},
        "submission_owner": owner,
    }
    if run_id is not None:
        request["run"] = {"id": run_id}
    return request


def _with_starting_commit(runner: CommandRunner, root: Path, request: dict[str, Any]) -> dict[str, Any]:
    result = _git(runner, root, ["rev-parse", "HEAD"])
    if result.returncode != 0:
        backend_fail("project gate failed — could not resolve the delivery worktree head")
    request["delivery"]["starting_commit"] = result.stdout.strip()
    return request


def _parse_result(raw: str) -> GateResult:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        backend_fail("project gate failed — adapter did not emit exactly one valid Gate result JSON")
    if not isinstance(value, dict):
        backend_fail("project gate failed — adapter did not emit exactly one valid Gate result JSON")
    status = value.get("status")
    summary = value.get("summary")
    assessed_commit = value.get("assessed_commit")
    run = value.get("run")
    if run is not None and not isinstance(run, dict):
        backend_fail("project gate failed — adapter emitted a malformed Gate result")
    run_id = run.get("id") if isinstance(run, dict) else None
    if status not in {"passed", "failed", "pending"} or not isinstance(summary, str) or not isinstance(assessed_commit, str) or not assessed_commit:
        backend_fail("project gate failed — adapter emitted a malformed Gate result")
    if run is not None and (not isinstance(run_id, str) or not run_id):
        backend_fail("project gate failed — adapter emitted a malformed Gate result")
    if status == "pending" and run_id is None:
        backend_fail("project gate failed — pending Gate result requires run.id")
    delivery = value.get("delivery")
    completed = isinstance(delivery, dict) and delivery.get("status") == "completed"
    return GateResult(status, summary, assessed_commit, run_id, completed)


def _invoke(runner: CommandRunner, root: Path, config: GateConfig, operation: str, request: Mapping[str, Any]) -> GateResult:
    source = _adapter_source(runner, root, config)
    fd, executable = tempfile.mkstemp(prefix="clerk-project-gate-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as adapter_file:
            adapter_file.write(source)
        os.chmod(executable, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        result = runner.run([executable, operation], cwd=root, input=json.dumps(request) + "\n")
    finally:
        Path(executable).unlink(missing_ok=True)
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail("project gate failed — adapter execution failed")
    gate_result = _parse_result(result.stdout)
    assessed = _git(runner, root, ["rev-parse", "--verify", "--quiet", f"{gate_result.assessed_commit}^{{commit}}"])
    if assessed.returncode != 0:
        backend_fail("project gate failed — adapter emitted an unknown assessed_commit")
    return gate_result


def _state_path(runner: CommandRunner, root: Path, short: str) -> Path:
    result = _git(runner, root, ["rev-parse", "--git-path", f"clerk/gates/{short}.json"])
    if result.returncode != 0 or not result.stdout.strip():
        backend_fail("project gate failed — could not locate Gate-run metadata")
    path = Path(result.stdout.strip())
    return path if path.is_absolute() else root / path


def _save_pending(runner: CommandRunner, root: Path, short: str, request: Mapping[str, Any], run_id: str) -> None:
    path = _state_path(runner, root, short)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"request": request, "run_id": run_id}) + "\n", encoding="utf-8")


def _load_pending(runner: CommandRunner, root: Path, short: str) -> tuple[dict[str, Any], str]:
    path = _state_path(runner, root, short)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        request, run_id = value["request"], value["run_id"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError):
        usage("clerk backlog gate: no pending Project-gate run for this Work")
    if not isinstance(request, dict) or not isinstance(run_id, str) or not run_id:
        usage("clerk backlog gate: no pending Project-gate run for this Work")
    return request, run_id


def _clear_pending(runner: CommandRunner, root: Path, short: str) -> None:
    _state_path(runner, root, short).unlink(missing_ok=True)


def _record_terminal(runner: CommandRunner, root: Path, short: str, request: Mapping[str, Any], result: GateResult) -> None:
    path = _state_path(runner, root, short).with_suffix(".result.json")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "request": request,
                "result": {
                    "status": result.status,
                    "summary": result.summary,
                    "assessed_commit": result.assessed_commit,
                    **({"run": {"id": result.run_id}} if result.run_id else {}),
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )


def _close_work(backend: str, runner: CommandRunner, id_: str) -> None:
    if backend == "bd":
        try:
            BdWorkGraphAdapter(runner).complete_delivery(id_)
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"project gate failed — could not confirm project-gate delivery completion: {exc}")
        return
    result = runner.run(["gh", "issue", "close", id_])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail("project gate failed — could not record project-gate delivery completion")


def _handoff(runner: CommandRunner, root: Path, branch: str, title: str, work_id: str, summary: str, acceptance: str) -> None:
    result = _git(runner, root, ["push", "-u", "origin", branch])
    if result.returncode != 0:
        backend_fail(f"submit failed — could not push {branch} to origin")
    result = runner.run(
        [
            "gh",
            "pr",
            "create",
            "--head",
            branch,
            "--base",
            "main",
            "--title",
            f"{title} ({work_id})",
            "--body",
            f"## Project gate\n\n{summary}\n\n## Acceptance criteria\n\n{acceptance}",
        ]
    )
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail("submit failed — gh pr create did not succeed")
    if _PR_URL.fullmatch(result.stdout) is None:
        backend_fail("submit failed — gh pr create did not emit exactly one well-formed GitHub pull-request URL")


def _finish_terminal(backend: str, runner: CommandRunner, root: Path, config: GateConfig, result: GateResult, work_id: str, title: str, acceptance: str, branch: str, short: str, env: Mapping[str, str]) -> int:
    if result.status == "failed":
        print(f"clerk: project gate failed for {work_id}: {result.summary}", file=sys.stderr)
        return 6
    if result.status == "pending":
        assert result.run_id is not None
        request = _with_starting_commit(runner, root, _request(work_id, title, acceptance, branch, root, config.submission_owner))
        _save_pending(runner, root, short, request, result.run_id)
        _success(f"project gate pending for {work_id}: {result.summary}", env)
        return 0
    if config.submission_owner == "clerk":
        head = _git(runner, root, ["rev-parse", "HEAD"])
        if head.returncode != 0 or head.stdout.strip() != result.assessed_commit:
            backend_fail("project gate failed — passed assessed_commit is not the current delivery worktree head")
        _handoff(runner, root, branch, title, work_id, result.summary, acceptance)
        _success(f"submitted {work_id} — project gate passed; PR created", env)
        return 0
    if not result.delivery_completed:
        backend_fail("project gate failed — project-gate-owned passed result must report delivery.status 'completed'")
    _close_work(backend, runner, work_id)
    _success(f"completed {work_id} — project gate owns delivery", env)
    return 0


def cmd_backlog_submit(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if len(argv) != 1:
        usage("clerk backlog submit: usage: clerk backlog submit <id>")
    work_id, title, acceptance = _work(backend, runner, argv[0], "clerk backlog submit")
    if not acceptance:
        usage(f"clerk backlog submit: {work_id} has no acceptance criteria — return it to discovery before submitting")
    short = _short(work_id)
    branch = f"delivery/{short}"
    if _current_branch(runner, root) != branch:
        usage(f"clerk backlog submit: not inside {branch} — claim {work_id} first")
    config = _load_config(runner, root)
    _clear_pending(runner, root, short)
    request = _with_starting_commit(runner, root, _request(work_id, title, acceptance, branch, root, config.submission_owner))
    result = _invoke(runner, root, config, "run", request)
    if result.status == "pending":
        assert result.run_id is not None
        _save_pending(runner, root, short, request, result.run_id)
        _success(f"project gate pending for {work_id}: {result.summary}", env)
        return 0
    _record_terminal(runner, root, short, request, result)
    return _finish_terminal(backend, runner, root, config, result, work_id, title, acceptance, branch, short, env)


def cmd_backlog_gate(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if len(argv) != 1:
        usage("clerk backlog gate: usage: clerk backlog gate <id>")
    requested_id = argv[0]
    short = _short(requested_id)
    branch = f"delivery/{short}"
    if _current_branch(runner, root) != branch:
        usage(f"clerk backlog gate: not inside {branch} — claim {requested_id} first")
    current_work_id = ""
    if backend == "bd":
        current_work_id, _, current_acceptance = _work(backend, runner, requested_id, "clerk backlog gate")
        if not current_acceptance:
            usage(f"clerk backlog gate: {current_work_id} has no acceptance criteria — return it to discovery before submitting")
    request, run_id = _load_pending(runner, root, short)
    work = request.get("work")
    if (
        not isinstance(work, dict)
        or not isinstance(work.get("id"), str)
        or not isinstance(work.get("title"), str)
        or not isinstance(work.get("acceptance_criteria"), str)
        or not work["acceptance_criteria"]
        or (current_work_id and work["id"] != current_work_id)
    ):
        backend_fail("project gate failed — pending Gate-run metadata is malformed")
    work_id, title, acceptance = work["id"], work["title"], work["acceptance_criteria"]
    config = _load_config(runner, root)
    request = dict(request)
    request["run"] = {"id": run_id}
    result = _invoke(runner, root, config, "status", request)
    if result.status == "pending":
        assert result.run_id is not None
        _save_pending(runner, root, short, request, result.run_id)
        _success(f"project gate pending for {work_id}: {result.summary}", env)
        return 0
    _clear_pending(runner, root, short)
    _record_terminal(runner, root, short, request, result)
    return _finish_terminal(backend, runner, root, config, result, work_id, title, acceptance, branch, short, env)
