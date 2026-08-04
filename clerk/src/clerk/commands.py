"""Python-owned Clerk command implementations."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import sys
from collections.abc import Mapping, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .output import Palette
from .proc import CommandResult, CommandRunner
from .work_graph import (
    BdWorkGraphAdapter,
    Work,
    WorkGraph,
    WorkGraphBackendError,
    has_acceptance_criteria,
    has_blocker as _has_block_edge,
    has_open_blockers,
    has_open_children,
    is_active_inbox as _is_active_inbox,
    is_nonclosed_work as _is_nonclosed_work,
    is_open_inbox as _is_open_inbox,
    is_ready_promoted as _is_ready_promoted,
    parent_id,
    shares_parent,
)

_PREGRILL_RE = re.compile(r"clerk-pregrill: ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)")

# C-e (acceptance-criteria detection, `inbox ready`): presence of a structural section only;
# never a quality judgment. A markdown heading (any '#' depth) or a bare
# "Acceptance Criteria[:]" line counts; prose that merely mentions the phrase does not.
_ACCEPTANCE_SECTION_RE = re.compile(
    r"^#{1,6}\s*acceptance criteria|^acceptance criteria:?\s*$",
    re.IGNORECASE | re.MULTILINE,
)


def has_acceptance_criteria_section(combined: str) -> bool:
    """Whether the combined description+design prose carries an Acceptance Criteria section."""
    return _ACCEPTANCE_SECTION_RE.search(combined or "") is not None


class ClerkExit(Exception):
    def __init__(self, code: int) -> None:
        self.code = code


def usage(message: str) -> None:
    print(message, file=sys.stderr)
    raise ClerkExit(2)


def backend_fail(message: str) -> None:
    print(f"clerk: {message}", file=sys.stderr)
    print("       run 'clerk doctor' to check the backend", file=sys.stderr)
    raise ClerkExit(5)


def _emit_stderr(result: CommandResult) -> None:
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)


def _json_from_result(result: CommandResult, message: str) -> Any:
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(message)
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        backend_fail(message)


def _bd_issue_json_or_usage(runner: CommandRunner, id_: str, verb: str, hint: str = "'clerk inbox list' shows open units") -> dict[str, Any]:
    result = runner.run(["bd", "show", id_, "--readonly", "--json"])
    if result.returncode != 0 and not result.stdout.strip():
        usage(f"{verb}: {id_} not found — check the id ({hint})")
    try:
        data = json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        backend_fail(f"{verb.removeprefix('clerk ')} failed — bd show did not return valid JSON for {id_}")
    if not isinstance(data, list) or not data:
        usage(f"{verb}: {id_} not found — check the id ({hint})")
    obj = data[0]
    if not isinstance(obj, dict):
        backend_fail(f"{verb.removeprefix('clerk ')} failed — bd show did not return an issue object for {id_}")
    return obj


def _bd_issue_json_or_backend(runner: CommandRunner, id_: str, message: str) -> dict[str, Any]:
    result = runner.run(["bd", "show", id_, "--readonly", "--json"])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(message)
    try:
        data = json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        backend_fail(message)
    if not isinstance(data, list) or not data or not isinstance(data[0], dict):
        backend_fail(message)
    return data[0]


def _pregrill_epoch(value: str) -> int | None:
    try:
        dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None
    return int(dt.timestamp())


def _pregrill_marker(notes: str, updated_at: str, env: Mapping[str, str]) -> str:
    matches = _PREGRILL_RE.findall(notes or "")
    if not matches:
        return "absent"
    note_epoch = _pregrill_epoch(matches[-1])
    updated_epoch = _pregrill_epoch(updated_at or "")
    if note_epoch is None or updated_epoch is None:
        return "stale"
    try:
        tolerance = int(env.get("CLERK_PREGRILL_STALE_TOLERANCE_S", "10"))
    except ValueError:
        tolerance = 10
    return "stale" if updated_epoch - note_epoch > tolerance else "present"


def _dump_json(value: Any, *, pretty: bool) -> str:
    if pretty:
        return json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n"


def _success(message: str, env: Mapping[str, str]) -> None:
    palette = Palette.from_env(env)
    print(f"{palette.green}clerk:{palette.reset} {message}")


def _body_guard(updated_at: str, body: str) -> str:
    # Match legacy command-substitution behavior: trailing newlines are stripped before
    # hashing the guarded body, while embedded newlines remain significant.
    guard_body = body.rstrip("\n")
    return hashlib.sha256(updated_at.encode() + b"\0" + guard_body.encode()).hexdigest()


def _read_stdin_trimmed() -> str:
    return sys.stdin.read().rstrip("\n")


def _read_file_trimmed(path: str, verb: str, *, body: bool = False) -> str:
    file_path = Path(path)
    if not file_path.is_file():
        if body:
            usage(f"{verb}: body file not found: {path}")
        usage(f"{verb}: file not found: {path}")
    return file_path.read_text().rstrip("\n")


def _read_nonempty_text_arg(verb: str, argv: Sequence[str]) -> str:
    input_source = "stdin"
    file = ""
    input_seen = False
    args = list(argv)
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--file":
            if i + 1 >= len(args):
                usage(f"{verb}: --file needs a path")
            if input_seen:
                usage(f"{verb}: choose only one input source")
            input_source = "file"
            input_seen = True
            file = args[i + 1]
            i += 2
        elif arg == "--stdin":
            if input_seen:
                usage(f"{verb}: choose only one input source")
            input_source = "stdin"
            input_seen = True
            i += 1
        else:
            usage(f"{verb}: unknown argument '{arg}'")
    text = _read_file_trimmed(file, verb) if input_source == "file" else _read_stdin_trimmed()
    if not re.search(r"\S", text):
        usage(f"{verb}: note text must be non-empty")
    return text


def _status_labels(obj: Mapping[str, Any]) -> dict[str, Any]:
    return {"status": obj.get("status"), "labels": obj.get("labels")}


def _bd_custom_types_csv(runner: CommandRunner) -> str:
    result = runner.run(["bd", "config", "get", "types.custom"])
    current = result.stdout.strip() if result.returncode == 0 else ""
    if "(not set)" in current:
        return ""
    return current


def _bd_ensure_impediment_type(runner: CommandRunner) -> None:
    current = _bd_custom_types_csv(runner)
    values = [value.strip() for value in current.split(",") if value.strip()]
    if "impediment" in values:
        return
    next_value = "impediment" if not current else f"{current},impediment"
    runner.run(["bd", "config", "set", "types.custom", next_value])


def _clerk_type_valid(runner: CommandRunner, type_: str) -> bool:
    if type_ in {"bug", "feature", "task", "epic", "chore", "decision"}:
        return True
    if type_ == "impediment":
        return True
    return type_ in [value.strip() for value in _bd_custom_types_csv(runner).split(",")]


def _build_pregrill_note(ts: str, decisions: Sequence[str], premises: Sequence[str], criteria: Sequence[str]) -> str:
    lines = [f"clerk-pregrill: {ts}", "Open decisions:"]
    lines.extend([f"- {decision}" for decision in decisions] or ["- (none)"])
    lines.append("Premises:")
    if premises:
        for premise in premises:
            if "|" in premise:
                text, verification = premise.split("|", 1)
            else:
                text, verification = premise, "not yet specified"
            lines.append(f"- {text} (verify: {verification})")
    else:
        lines.append("- (none)")
    lines.append("Draft acceptance criteria:")
    lines.extend([f"- {criterion}" for criterion in criteria] or ["- (none)"])
    return "\n".join(lines)


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _returned_short_from_id(id_: str) -> str:
    token = id_[1:] if id_.startswith("#") else id_
    return token.split("-", 1)[1] if "-" in token else token


def _git(runner: CommandRunner, root: Path, args: Sequence[str]) -> CommandResult:
    return runner.run(["git", "-C", str(root), *args])


def _primary_repo_root(runner: CommandRunner, root: Path) -> Path:
    result = _git(runner, root, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
    if result.returncode != 0:
        return root
    common = result.stdout.strip()
    if common.endswith("/.git"):
        return Path(common).parent
    return root


def _show_ref(runner: CommandRunner, root: Path, ref: str) -> bool:
    return _git(runner, root, ["show-ref", "--verify", "--quiet", ref]).returncode == 0


def _returned_attempt_refs(runner: CommandRunner, root: Path, id_: str) -> tuple[bool, bool]:
    if not (root / ".git").exists():
        return False, False
    main_root = _primary_repo_root(runner, root)
    short = _returned_short_from_id(id_)
    return (
        _show_ref(runner, main_root, f"refs/heads/returned/{short}"),
        _show_ref(runner, main_root, f"refs/remotes/origin/returned/{short}"),
    )


def returned_attempt_banner(runner: CommandRunner, root: Path, short: str, id_: str, dispose_hint: str) -> None:
    main_root = _primary_repo_root(runner, root)
    local_present, remote_present = _returned_attempt_refs(runner, root, id_)
    if not local_present and not remote_present:
        return
    if local_present and remote_present:
        presence = "local+origin"
    elif local_present:
        presence = "local"
    else:
        presence = "origin"
    ref = f"returned/{short}" if local_present else f"origin/returned/{short}"
    behind_result = _git(runner, main_root, ["rev-list", "--count", f"{ref}..main"])
    behind = behind_result.stdout.strip() if behind_result.returncode == 0 and behind_result.stdout.strip() else "?"
    subject_result = _git(runner, main_root, ["log", "-1", "--format=%s", ref])
    subject = subject_result.stdout.rstrip("\n") if subject_result.returncode == 0 and subject_result.stdout else "(unknown subject)"
    print(f"\nclerk: returned attempt: returned/{short} ({presence}; {behind} commit(s) behind main)")
    print(f"  subject: {subject}")
    if dispose_hint == "backlog claim":
        print(f"  reuse via: clerk backlog claim {id_} --from-returned")
        print(f"  fresh via: clerk backlog claim {id_} --fresh --returned keep|discard")
    else:
        print(f"  dispose via: clerk {dispose_hint} {id_} --returned keep|discard")


def _planning_holder_refusal(verb: str, root: Path, obj: Mapping[str, Any], runner: CommandRunner, env: Mapping[str, str]) -> None:
    # Allows unclaimed items or items claimed by the current actor; refuses (exit 5)
    # anything held by a different actor. Matches legacy `planning_holder_refusal`.
    holder = str(obj.get("assignee") or "")
    if not holder:
        return
    me = _claim_current_actor(runner, root, env)
    if holder == me:
        return
    print(f"clerk: {verb} refused — {obj.get('id')} is claimed by {holder}", file=sys.stderr)
    raise ClerkExit(5)


def _returned_branch_exists(runner: CommandRunner, root: Path, short: str) -> bool:
    if not (root / ".git").exists():
        return False
    main_root = _primary_repo_root(runner, root)
    if _show_ref(runner, main_root, f"refs/heads/returned/{short}"):
        return True
    return _show_ref(runner, main_root, f"refs/remotes/origin/returned/{short}")


def _delivery_branch_exists(runner: CommandRunner, root: Path, short: str) -> bool:
    if not (root / ".git").exists():
        return False
    main_root = _primary_repo_root(runner, root)
    return _show_ref(runner, main_root, f"refs/heads/delivery/{short}") or _show_ref(runner, main_root, f"refs/remotes/origin/delivery/{short}")


def _for_each_ref(runner: CommandRunner, main_root: Path, patterns: Sequence[str]) -> list[str]:
    result = _git(runner, main_root, ["for-each-ref", "--format=%(refname:short)", *patterns])
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _dispose_returned(runner: CommandRunner, root: Path, short: str, env: Mapping[str, str]) -> bool:
    # Delete the canonical `returned/<short>` ref plus any archived `returned/<short>-*`
    # siblings from both the local and origin refs, mirroring legacy `dispose_returned`.
    # Returns True when fully disposed; False when the remote delete was deferred to the
    # next `clerk sync` because the repository was offline.
    main_root = _primary_repo_root(runner, root)
    local_refs = _for_each_ref(runner, main_root, [f"refs/heads/returned/{short}", f"refs/heads/returned/{short}-*"])
    remote_refs_present = _for_each_ref(runner, main_root, [f"refs/remotes/origin/returned/{short}", f"refs/remotes/origin/returned/{short}-*"])
    if not local_refs and not remote_refs_present:
        return True
    for ref in local_refs:
        result = _git(runner, main_root, ["branch", "-D", ref])
        if result.returncode != 0:
            backend_fail(f"returned disposition failed — could not delete local {ref}")
    fetch_env = {**env, "GIT_TERMINAL_PROMPT": "0"}
    fetch_result = runner.run(["git", "-C", str(main_root), "fetch", "origin"], env=fetch_env)
    del fetch_env
    if fetch_result.returncode != 0:
        print(
            f"clerk: OFFLINE - returned/{short} and archives deleted locally only; the remote branch delete is deferred to sync (clerk sync will finish it at the next reconnect).",
            file=sys.stderr,
        )
        return False
    remote_refs = _for_each_ref(runner, main_root, [f"refs/remotes/origin/returned/{short}", f"refs/remotes/origin/returned/{short}-*"])
    for ref in remote_refs:
        branch = ref.removeprefix("origin/")
        result = _git(runner, main_root, ["push", "origin", "--delete", branch])
        if result.returncode != 0:
            backend_fail(f"returned disposition failed — could not delete origin {branch}")
        _git(runner, main_root, ["update-ref", "-d", f"refs/remotes/origin/{branch}"])
    return True


def _handle_returned_disposition(verb: str, root: Path, short: str, disposition: str, runner: CommandRunner, env: Mapping[str, str]) -> None:
    if not disposition:
        if _returned_branch_exists(runner, root, short):
            usage(f"clerk {verb}: returned/{short} exists — choose --returned keep or --returned discard")
        return
    if disposition == "keep":
        return
    if disposition == "discard":
        _dispose_returned(runner, root, short, env)
        return
    usage(f"clerk {verb}: --returned must be keep or discard")


def cmd_inbox_list(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    limit = ""
    args = list(argv)
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--limit":
            if i + 1 >= len(args):
                usage("clerk inbox list: --limit needs a value — usage: clerk inbox list [--limit <n>]")
            value = args[i + 1]
            if not value.isdigit():
                usage("clerk inbox list: --limit must be a non-negative integer")
            limit = value
            i += 2
        else:
            usage(f"clerk inbox list: unknown argument '{arg}' — usage: clerk inbox list [--limit <n>]")
    bd_args = ["bd", "list", "--status", "open", "--exclude-label", "stage:ready", "--readonly", "--json"]
    if limit:
        bd_args.extend(["--limit", limit])
    data = _json_from_result(runner.run(bd_args), "inbox list failed — bd list did not succeed")
    if not isinstance(data, list):
        backend_fail("inbox list failed — bd list did not return an issue list")
    print(f"Inbox (open, not ready) — {len(data)} item(s):")
    if not data:
        print("  (empty)")
        return 0
    for item in data:
        if not isinstance(item, dict):
            backend_fail("inbox list failed — bd list did not return issue objects")
        marker = _pregrill_marker(str(item.get("notes") or ""), str(item.get("updated_at") or ""), env)
        print(f"  {item.get('id', '')}  [pregrill:{marker}]  {item.get('title', '')}")
    return 0


def cmd_inbox_show(_backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox show: missing id — usage: clerk inbox show <id> [--json|--pretty]")
    id_ = argv[0]
    json_mode = False
    pretty = False
    for arg in argv[1:]:
        if arg == "--json":
            json_mode = True
        elif arg == "--pretty":
            json_mode = True
            pretty = True
        else:
            usage(f"clerk inbox show: unknown argument '{arg}' — usage: clerk inbox show <id> [--json|--pretty]")
    if json_mode:
        obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox show")
        updated = str(obj.get("updated_at") or "")
        body = str(obj.get("description") or "")
        # Legacy computes this through jq -r inside command substitution, so trailing
        # newlines are stripped for the guard even though the rendered body stays intact.
        guard_body = body.rstrip("\n")
        guard = _body_guard(updated, guard_body)
        rendered = {
            "id": obj.get("id"),
            "title": obj.get("title"),
            "status": obj.get("status"),
            "type": obj.get("issue_type"),
            "assignee": obj.get("assignee") or "",
            "labels": obj.get("labels") or [],
            "parent": obj.get("parent") if obj.get("parent") is not None else None,
            "body": body,
            "body_guard": guard,
            "notes": obj.get("notes") or "",
            "design": obj.get("design") or "",
            "acceptance": obj.get("acceptance_criteria") or "",
            "created_at": obj.get("created_at"),
            "updated_at": obj.get("updated_at"),
        }
        print(_dump_json(rendered, pretty=pretty), end="")
        return 0
    _bd_issue_json_or_usage(runner, id_, "clerk inbox show")
    result = runner.run(["bd", "show", id_, "--readonly"])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox show failed — bd show did not succeed for {id_}")
    print(result.stdout, end="")
    returned_attempt_banner(runner, root, _returned_short_from_id(id_), id_, "inbox ready|drop")
    return 0


def cmd_inbox_dups(_backend: str, _root: Path, _argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    data = _json_from_result(runner.run(["bd", "find-duplicates", "--readonly", "--json"]), "inbox dups failed — bd find-duplicates did not succeed")
    if not isinstance(data, dict):
        backend_fail("inbox dups failed — bd find-duplicates did not return an object")
    count = data.get("count") or 0
    print(f"Duplicate candidates — {count} pair(s):")
    if count == 0:
        print("  (none)")
        return 0
    for pair in data.get("pairs") or []:
        print(
            f"  {pair.get('issue_a_id')} \"{pair.get('issue_a_title')}\"  ~  "
            f"{pair.get('issue_b_id')} \"{pair.get('issue_b_title')}\"  (score: {pair.get('similarity')})"
        )
    return 0


def _claim_conflict(message: str) -> None:
    print(message, file=sys.stderr)
    raise ClerkExit(5)


def _graph_usage_text(kind: str) -> str:
    target = "parent" if kind in {"children", "frontier"} else "id"
    display = "<parent>" if target == "parent" else "<id>"
    return f"clerk inbox {kind} {display} [--pretty]"


def _parse_graph_query_args(kind: str, argv: Sequence[str]) -> tuple[str, bool]:
    if not argv:
        if kind in {"children", "frontier"}:
            usage(f"clerk inbox {kind}: missing parent id — usage: {_graph_usage_text(kind)}")
        usage(f"clerk inbox {kind}: missing id — usage: {_graph_usage_text(kind)}")
    id_ = argv[0]
    pretty = False
    for arg in argv[1:]:
        if arg == "--pretty":
            pretty = True
        else:
            usage(f"clerk inbox {kind}: unknown argument '{arg}' — usage: {_graph_usage_text(kind)}")
    return id_, pretty


def _graph_item(item: Work) -> dict[str, Any]:
    obj = item.raw
    return {
        "id": item.id,
        "title": item.title,
        "status": item.status,
        "type": obj.get("issue_type"),
        "assignee": item.assignee,
        "labels": list(item.labels),
        "parent": item.parent or None,
        "created_at": obj.get("created_at"),
        "updated_at": obj.get("updated_at"),
    }


def _bd_graph(runner: CommandRunner, kind: str) -> WorkGraph:
    try:
        return BdWorkGraphAdapter(runner).load()
    except WorkGraphBackendError as exc:
        _emit_stderr(exc.result)
        backend_fail(f"inbox {kind} failed — {exc}")


def _graph_work_or_usage(graph: WorkGraph, id_: str, kind: str) -> Work:
    item = graph.get(id_)
    if item is None:
        usage(f"clerk inbox {kind}: {id_} not found — check the id ('clerk inbox list' shows open units)")
    return item


def cmd_inbox_children(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("children", argv)
    graph = _bd_graph(runner, "children")
    parent = _graph_work_or_usage(graph, id_, "children")
    rendered = {"parent": _graph_item(parent), "items": [_graph_item(item) for item in graph.children(parent)]}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_inbox_blockers(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("blockers", argv)
    graph = _bd_graph(runner, "blockers")
    item = _graph_work_or_usage(graph, id_, "blockers")
    rendered = {"item": _graph_item(item), "items": [_graph_item(blocker) for blocker in graph.blockers(item)]}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_inbox_blocked(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("blocked", argv)
    graph = _bd_graph(runner, "blocked")
    item = _graph_work_or_usage(graph, id_, "blocked")
    rendered = {"item": _graph_item(item), "items": [_graph_item(blocked) for blocked in graph.blocked_by(item)]}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_inbox_frontier(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("frontier", argv)
    graph = _bd_graph(runner, "frontier")
    parent = _graph_work_or_usage(graph, id_, "frontier")
    if parent.status == "closed":
        usage(f"clerk inbox frontier: {id_} must be a non-closed Work graph parent")
    rendered = {"parent": _graph_item(parent), "items": [_graph_item(item) for item in graph.frontier(parent)]}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_backlog_next(backend: str, root: Path, _argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    if backend == "bd":
        try:
            pickable = BdWorkGraphAdapter(runner).backlog().pickable
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"backlog next failed — {exc}")
        print(f"Backlog (ready) — {len(pickable)} item(s):")
        if not pickable:
            print("  (empty)")
            return 0
        for item in pickable:
            marker = "returned" if any(_returned_attempt_refs(runner, root, item.id)) else "ready"
            print(f"  {item.id}  {marker}  {item.title}")
        return 0
    data = _json_from_result(runner.run(["gh", "issue", "list", "--label", "ready-for-agent", "--json", "number,title"]), "backlog next failed — gh issue list did not succeed")
    if not isinstance(data, list):
        backend_fail("backlog next failed — gh issue list did not return an issue list")
    print(f"Backlog (ready) — {len(data)} item(s):")
    if not data:
        print("  (empty)")
        return 0
    for item in data:
        if not isinstance(item, dict):
            backend_fail("backlog next failed — gh issue list did not return issue objects")
        print(f"  #{item.get('number')}  ready  {item.get('title', '')}")
    return 0


def cmd_backlog_waiting(backend: str, _root: Path, _argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    if backend == "bd":
        try:
            waiting = BdWorkGraphAdapter(runner).backlog().waiting
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"backlog waiting failed — {exc}")
        print(f"Backlog waiting — {len(waiting)} item(s):")
        if not waiting:
            print("  (empty)")
            return 0
        for item in waiting:
            print(f"  {item.work.id}  blockers:{item.blocker_count} children:{item.child_count}  {item.work.title}")
        return 0
    print("Backlog waiting — 0 item(s):\n  (empty)")
    return 0


def cmd_backlog_resolve(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk backlog resolve: missing id — usage: clerk backlog resolve <id> [--returned keep|discard] [--file <path>|--stdin]")
    id_ = argv[0]
    returned_disposition = ""
    input_args: list[str] = []
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--returned":
            if i + 1 >= len(args):
                usage("clerk backlog resolve: --returned needs keep or discard")
            returned_disposition = args[i + 1]
            i += 2
        elif arg == "--file":
            if i + 1 >= len(args):
                usage("clerk backlog resolve: --file needs a path")
            input_args.extend(args[i:i + 2])
            i += 2
        elif arg == "--stdin":
            input_args.append(arg)
            i += 1
        else:
            usage(f"clerk backlog resolve: unknown argument '{arg}' — usage: clerk backlog resolve <id> [--returned keep|discard] [--file <path>|--stdin]")
    if returned_disposition not in {"", "keep", "discard"}:
        usage("clerk backlog resolve: --returned must be keep or discard")
    if backend != "bd":
        print("clerk: 'backlog resolve (gh)' is not yet implemented in this generation (see dotfiles-dft epic)", file=sys.stderr)
        raise ClerkExit(3)

    adapter = BdWorkGraphAdapter(runner)
    try:
        graph = adapter.load()
    except WorkGraphBackendError as exc:
        _emit_stderr(exc.result)
        backend_fail(f"backlog resolve failed — {exc}")
    item = graph.resolve(id_)
    if item is None:
        usage(f"clerk backlog resolve: {id_} not found — check the id ('clerk backlog next' shows ready units)")
    if not has_acceptance_criteria(item.raw):
        usage(f"clerk backlog resolve: {item.id} has no 'Acceptance Criteria' section — it needs a grill pass before no-code resolution")

    reasons = list(graph.pickability_reasons(item))
    short = _returned_short_from_id(item.id)
    if _delivery_branch_exists(runner, root, short):
        reasons.append(f"claimed by delivery/{short}")
    if reasons:
        usage(f"clerk backlog resolve: {item.id} is not pickable — {', '.join(reasons)}")
    _handle_returned_disposition("backlog resolve", root, short, returned_disposition, runner, env)

    text = _read_nonempty_text_arg("clerk backlog resolve", input_args)
    note = f"clerk-backlog-resolution: {_utc_timestamp()}\n{text}"
    result = adapter.append_notes(item.id, note)
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"backlog resolve failed — could not append resolution note for {item.id}")
    result = adapter.close(item.id, "resolved without delivery")
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"backlog resolve failed — bd close did not succeed for {item.id}")
    try:
        after = adapter.inspect(item.id)
    except WorkGraphBackendError as exc:
        _emit_stderr(exc.result)
        backend_fail(f"backlog resolve failed — {item.id} was not confirmed closed as resolved without delivery")
    if str(after.get("status") or "") != "closed" or str(after.get("close_reason") or "") != "resolved without delivery":
        backend_fail(f"backlog resolve failed — {item.id} was not confirmed closed as resolved without delivery")
    if note not in str(after.get("notes") or ""):
        backend_fail(f"backlog resolve failed — resolution note was not confirmed for {item.id}")
    _success(f"resolved {item.id} without delivery", env)
    return 0


def cmd_backlog_show(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk backlog show: missing id — usage: clerk backlog show <id>")
    id_ = argv[0]
    if backend == "bd":
        _bd_issue_json_or_usage(runner, id_, "clerk backlog show", "'clerk backlog next' shows open units")
        result = runner.run(["bd", "show", id_, "--readonly"])
        _emit_stderr(result)
        if result.returncode != 0:
            backend_fail(f"backlog show failed — bd show did not succeed for {id_}")
        print(result.stdout, end="")
    else:
        result = runner.run(["gh", "issue", "view", id_])
        _emit_stderr(result)
        if result.returncode != 0:
            if "not found" in result.stderr.lower():
                usage(f"clerk backlog show: {id_} not found — check the id ('clerk backlog next' shows open units)")
            backend_fail(f"backlog show failed — gh issue view did not succeed for {id_}")
        print(result.stdout, end="")
    returned_attempt_banner(runner, root, _returned_short_from_id(id_), id_, "backlog claim")
    return 0


def cmd_capture(backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage('clerk capture: missing title — usage: clerk capture "<title>" [--stdin|--type <type>|--impediment|--parent <id>|--blocked-by <id>]')
    title = argv[0]
    use_stdin = False
    use_impediment = False
    issue_type = ""
    parent = ""
    blockers: list[str] = []
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--stdin":
            use_stdin = True
            i += 1
        elif arg == "--impediment":
            use_impediment = True
            i += 1
        elif arg == "--type":
            if i + 1 >= len(args):
                usage("clerk capture: --type needs a value")
            issue_type = args[i + 1]
            i += 2
        elif arg == "--parent":
            if i + 1 >= len(args):
                usage("clerk capture: --parent needs a Work graph id")
            parent = args[i + 1]
            i += 2
        elif arg == "--blocked-by":
            if i + 1 >= len(args):
                usage("clerk capture: --blocked-by needs a Work graph sibling id")
            blockers.append(args[i + 1])
            i += 2
        else:
            usage(f'clerk capture: unknown argument \'{arg}\' — usage: clerk capture "<title>" [--stdin|--type <type>|--impediment|--parent <id>|--blocked-by <id>]')

    if use_impediment and issue_type:
        usage("clerk capture: --impediment is compatibility sugar for --type impediment; do not combine them")
    if use_impediment:
        issue_type = "impediment"
    if issue_type and not _clerk_type_valid(runner, issue_type):
        usage(f"clerk capture: invalid --type '{issue_type}' — use a canonical core type or configure types.custom")
    if blockers and not parent:
        usage("clerk capture: --blocked-by requires --parent so the new dependency edge is sibling-only")

    if backend not in {"bd", "gh"}:
        backend_fail(f"capture failed — unsupported backend {backend}")
    if issue_type == "impediment":
        _bd_ensure_impediment_type(runner)
    if parent:
        parent_json = _bd_issue_json_or_usage(runner, parent, "clerk capture")
        if not _is_nonclosed_work(parent_json):
            usage(f"clerk capture: --parent {parent} must name a non-closed Work graph item")
    for blocker in blockers:
        blocker_json = _bd_issue_json_or_usage(runner, blocker, "clerk capture")
        if not _is_nonclosed_work(blocker_json):
            usage(f"clerk capture: --blocked-by {blocker} must name a non-closed Work graph item")
        if parent and parent_id(blocker_json) != parent:
            usage(f"clerk capture: --blocked-by {blocker} must be a sibling under {parent}")

    graph = BdWorkGraphAdapter(runner)
    result = graph.create(
        title,
        use_stdin=use_stdin,
        issue_type=issue_type,
        parent=parent,
        blockers=tuple(blockers),
    )
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f'capture failed — bd create did not succeed for "{title}"')
    id_ = result.stdout.strip()
    seen = _bd_issue_json_or_backend(runner, id_, f"capture failed — {id_} was not confirmed after creation")
    if seen.get("id") != id_:
        backend_fail(f"capture failed — {id_} was not confirmed after creation")
    if _is_ready_promoted(seen):
        result = graph.remove_ready_label(id_)
        _emit_stderr(result)
        if result.returncode != 0:
            backend_fail(f"capture failed — {id_} could not be restored to the Inbox")
        seen = _bd_issue_json_or_backend(runner, id_, f"capture failed — {id_} was not confirmed after restoring it to the Inbox")
        if seen.get("id") != id_ or _is_ready_promoted(seen):
            backend_fail(f"capture failed — {id_} remained ready after creation")
    suffix = " (type: impediment)" if issue_type == "impediment" else ""
    _success(f"filed {id_}{suffix}", env)
    return 0


def _claim_current_actor(runner: CommandRunner, root: Path, env: Mapping[str, str]) -> str:
    if env.get("BEADS_ACTOR"):
        return str(env["BEADS_ACTOR"])
    result = _git(runner, root, ["config", "user.name"])
    name = result.stdout.strip() if result.returncode == 0 else ""
    return name or str(env.get("USER") or "")


def cmd_inbox_parent(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox parent: usage: clerk inbox parent set <child> <parent> | clerk inbox parent clear <child>")
    action = argv[0]
    drop = False
    if action == "set":
        if len(argv) < 3:
            usage("clerk inbox parent set: usage: clerk inbox parent set <child> <parent> [--drop-invalid-deps]")
        child, parent = argv[1], argv[2]
        rest = list(argv[3:])
    elif action == "clear":
        if len(argv) < 2:
            usage("clerk inbox parent clear: usage: clerk inbox parent clear <child> [--drop-invalid-deps]")
        child, parent = argv[1], ""
        rest = list(argv[2:])
    else:
        usage("clerk inbox parent: usage: clerk inbox parent set <child> <parent> | clerk inbox parent clear <child>")
    for arg in rest:
        if arg == "--drop-invalid-deps":
            drop = True
        else:
            usage(f"clerk inbox parent {action}: unknown argument '{arg}'")

    adapter = BdWorkGraphAdapter(runner)
    child_json = _bd_issue_json_or_usage(runner, child, f"clerk inbox parent {action}")
    if not _is_open_inbox(child_json):
        usage(f"clerk inbox parent {action}: {child} must be an open inbox item")
    if parent:
        parent_json = _bd_issue_json_or_usage(runner, parent, "clerk inbox parent set")
        if not _is_open_inbox(parent_json):
            usage(f"clerk inbox parent set: {parent} must be an open inbox parent")
        try:
            cycle = adapter.parent_cycle_would_form(child, parent)
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"inbox parent set failed — {exc}")
        if cycle:
            usage(f"clerk inbox parent set: refusing parent cycle ({child} under {parent})")

    try:
        invalid = adapter.invalid_blockers_for_parent_move(child, parent, child_json)
    except WorkGraphBackendError as exc:
        _emit_stderr(exc.result)
        backend_fail(f"inbox parent {action} failed — {exc}")
    if invalid and not drop:
        usage(f"clerk inbox parent {action}: move would leave non-sibling dependency edges — rerun with --drop-invalid-deps to remove them")
    for dependent, blocker in invalid:
        result = adapter.remove_blocker(dependent, blocker)
        _emit_stderr(result)
        if result.returncode != 0:
            backend_fail(f"inbox parent {action} failed — could not drop invalid dependency {dependent} -> {blocker}")

    result = adapter.set_parent(child, parent)
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox parent {action} failed — bd update --parent did not succeed for {child}")
    after_child = _bd_issue_json_or_backend(runner, child, f"inbox parent {action} failed — parent was not confirmed for {child}")
    actual = parent_id(after_child)
    if actual != parent:
        backend_fail(f"inbox parent {action} failed — parent was not confirmed for {child}")
    for dependent, blocker in invalid:
        dependent_json = after_child if dependent == child else _bd_issue_json_or_backend(
            runner,
            dependent,
            f"inbox parent {action} failed — dropped invalid dependency was not confirmed for {dependent} -> {blocker}",
        )
        if _has_block_edge(dependent_json, blocker):
            backend_fail(f"inbox parent {action} failed — dropped invalid dependency was not confirmed for {dependent} -> {blocker}")
    _success(f"parent set {child} -> {parent}" if parent else f"parent cleared {child}", env)
    return 0


def cmd_inbox_dep(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox dep: usage: clerk inbox dep add <child> <blocker> | clerk inbox dep remove <child> <blocker>")
    action = argv[0]
    if action not in {"add", "remove"} or len(argv) < 3:
        usage(f"clerk inbox dep {action}: usage: clerk inbox dep {action} <child> <blocker>" if action in {"add", "remove"} else "clerk inbox dep: usage: clerk inbox dep add <child> <blocker> | clerk inbox dep remove <child> <blocker>")
    child, blocker = argv[1], argv[2]
    if len(argv) > 3:
        usage(f"clerk inbox dep {action}: unknown argument '{argv[3]}'")
    if child == blocker:
        usage(f"clerk inbox dep {action}: an item cannot block itself")
    adapter = BdWorkGraphAdapter(runner)
    child_json = _bd_issue_json_or_usage(runner, child, f"clerk inbox dep {action}")
    blocker_json = _bd_issue_json_or_usage(runner, blocker, f"clerk inbox dep {action}")
    if not _is_open_inbox(child_json):
        usage(f"clerk inbox dep {action}: {child} must be an open inbox item")
    if _is_ready_promoted(blocker_json):
        usage(f"clerk inbox dep {action}: {blocker} must be an inbox item, not a ready/promoted item")
    if not shares_parent(child_json, blocker_json):
        usage(f"clerk inbox dep {action}: dependency edges are sibling-only; {child} and {blocker} must share the same immediate parent")

    if action == "add":
        try:
            cycle = adapter.dependency_path_exists(blocker, child)
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail(f"inbox dep add failed — {exc}")
        if cycle:
            usage(f"clerk inbox dep add: refusing dependency cycle ({child} blocked by {blocker})")
        result = adapter.add_blocker(child, blocker)
        _emit_stderr(result)
        if result.returncode != 0:
            backend_fail(f"inbox dep add failed — bd dep add did not succeed for {child} <- {blocker}")
        after = _bd_issue_json_or_backend(runner, child, f"inbox dep add failed — edge was not confirmed for {child} <- {blocker}")
        if not _has_block_edge(after, blocker):
            backend_fail(f"inbox dep add failed — edge was not confirmed for {child} <- {blocker}")
        _success(f"dependency added {child} blocked-by {blocker}", env)
    else:
        result = adapter.remove_blocker(child, blocker)
        _emit_stderr(result)
        if result.returncode != 0:
            backend_fail(f"inbox dep remove failed — bd dep remove did not succeed for {child} <- {blocker}")
        after = _bd_issue_json_or_backend(runner, child, f"inbox dep remove failed — edge still exists for {child} <- {blocker}")
        if _has_block_edge(after, blocker):
            backend_fail(f"inbox dep remove failed — edge still exists for {child} <- {blocker}")
        _success(f"dependency removed {child} blocked-by {blocker}", env)
    return 0


def cmd_inbox_claim(_backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox claim: missing id — usage: clerk inbox claim <id>")
    id_ = argv[0]
    if len(argv) > 1:
        usage(f"clerk inbox claim: unknown argument '{argv[1]}' — usage: clerk inbox claim <id>")
    obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox claim")
    if not _is_active_inbox(obj):
        usage(f"clerk inbox claim: {id_} must be an open inbox item (not ready/promoted/closed)")
    holder = str(obj.get("assignee") or "")
    if holder:
        me = _claim_current_actor(runner, root, env)
        if holder == me:
            _success(f"{id_} already claimed by you", env)
            return 0
        _claim_conflict(f"clerk: inbox claim refused — {id_} is already claimed by {holder}")
    if not _is_open_inbox(obj):
        usage(f"clerk inbox claim: {id_} must be an open inbox item (not already in progress)")
    if has_open_blockers(obj):
        usage(f"clerk inbox claim: {id_} has open blockers — claim an unblocked frontier item")
    if has_open_children(obj):
        usage(f"clerk inbox claim: {id_} has open children — claim a leaf item, not its parent")
    me = _claim_current_actor(runner, root, env)
    result = runner.run(["bd", "update", id_, "--claim"])
    _emit_stderr(result)
    if result.returncode != 0:
        latest = _bd_issue_json_or_usage(runner, id_, "clerk inbox claim")
        holder = str(latest.get("assignee") or "")
        if holder and holder != me:
            _claim_conflict(f"clerk: inbox claim refused — {id_} is already claimed by {holder}")
        backend_fail(f"inbox claim failed — bd update --claim did not succeed for {id_}")
    check = str(_bd_issue_json_or_backend(runner, id_, f"inbox claim failed — {id_} was not confirmed claimed by {me}").get("assignee") or "")
    if check != me:
        backend_fail(f"inbox claim failed — {id_} was not confirmed claimed by {me}")
    _success(f"claimed {id_}", env)
    return 0


def cmd_inbox_release(_backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox release: missing id — usage: clerk inbox release <id>")
    id_ = argv[0]
    if len(argv) > 1:
        usage(f"clerk inbox release: unknown argument '{argv[1]}' — usage: clerk inbox release <id>")
    obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox release")
    me = _claim_current_actor(runner, root, env)
    holder = str(obj.get("assignee") or "")
    if not holder:
        _success(f"{id_} is not claimed — nothing to release", env)
        return 0
    if holder != me:
        _claim_conflict(f"clerk: inbox release refused — {id_} is claimed by {holder}")
    result = runner.run(["bd", "update", id_, "--status", "open", "--assignee", ""])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox release failed — bd update --status open --assignee did not succeed for {id_}")
    check = str(_bd_issue_json_or_backend(runner, id_, f"inbox release failed — {id_} was not confirmed unclaimed").get("assignee") or "")
    if check:
        backend_fail(f"inbox release failed — {id_} was not confirmed unclaimed")
    _success(f"released {id_}", env)
    return 0


def cmd_inbox_resolve(_backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox resolve: missing id — usage: clerk inbox resolve <id> [--file <path>|--stdin]")
    id_ = argv[0]
    obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox resolve")
    if not _is_active_inbox(obj):
        usage(f"clerk inbox resolve: {id_} must be an open inbox item (not ready/promoted/closed)")
    holder = str(obj.get("assignee") or "")
    if holder:
        me = _claim_current_actor(runner, root, env)
        if holder != me:
            _claim_conflict(f"clerk: inbox resolve refused — {id_} is claimed by {holder}")
    if has_open_blockers(obj):
        usage(f"clerk inbox resolve: {id_} has open blockers — resolve blockers first")
    if has_open_children(obj):
        usage(f"clerk inbox resolve: {id_} has open children — resolve or reparent children first")
    text = _read_nonempty_text_arg("clerk inbox resolve", argv[1:])
    ts = _utc_timestamp()
    note = f"clerk-resolution: {ts}\n{text}"
    result = runner.run(["bd", "update", id_, "--append-notes", note])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox resolve failed — could not append resolution note for {id_}")
    result = runner.run(["bd", "close", id_, "--reason", "resolved"])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox resolve failed — bd close did not succeed for {id_}")
    after = _bd_issue_json_or_backend(runner, id_, f"inbox resolve failed — {id_} was not confirmed closed")
    status = str(after.get("status") or "")
    if status != "closed":
        backend_fail(f"inbox resolve failed — {id_} was not confirmed closed")
    if note not in str(after.get("notes") or ""):
        backend_fail(f"inbox resolve failed — resolution note was not confirmed for {id_}")
    _success(f"resolved {id_}", env)
    return 0


def cmd_inbox_pregrill(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage('clerk inbox pregrill: missing id — usage: clerk inbox pregrill <id> [--decision "<text>"]... [--premise "<text>|<verification>"]... [--criterion "<text>"]...')
    id_ = argv[0]
    decisions: list[str] = []
    premises: list[str] = []
    criteria: list[str] = []
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--decision":
            if i + 1 >= len(args):
                usage("clerk inbox pregrill: --decision needs a value")
            decisions.append(args[i + 1])
            i += 2
        elif arg == "--premise":
            if i + 1 >= len(args):
                usage("clerk inbox pregrill: --premise needs a value")
            premises.append(args[i + 1])
            i += 2
        elif arg == "--criterion":
            if i + 1 >= len(args):
                usage("clerk inbox pregrill: --criterion needs a value")
            criteria.append(args[i + 1])
            i += 2
        else:
            usage(f"clerk inbox pregrill: unknown argument '{arg}'")
    before = _bd_issue_json_or_usage(runner, id_, "clerk inbox pregrill")
    status_labels_before = _status_labels(before)
    ts = _utc_timestamp()
    note = _build_pregrill_note(ts, decisions, premises, criteria)
    result = runner.run(["bd", "update", id_, "--append-notes", note])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox pregrill failed — bd update --append-notes did not succeed for {id_}")
    after = _bd_issue_json_or_backend(runner, id_, f"inbox pregrill failed — {id_} status/labels changed (not state-neutral)")
    if status_labels_before != _status_labels(after):
        backend_fail(f"inbox pregrill failed — {id_} status/labels changed (not state-neutral)")
    _success(f"pregrilled {id_} (dated {ts})", env)
    return 0


def cmd_inbox_note(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox note: missing id — usage: clerk inbox note <id> [--file <path>|--stdin]")
    id_ = argv[0]
    _bd_issue_json_or_usage(runner, id_, "clerk inbox note")
    text = _read_nonempty_text_arg("clerk inbox note", argv[1:])
    before = _bd_issue_json_or_usage(runner, id_, "clerk inbox note")
    status_labels_before = _status_labels(before)
    result = runner.run(["bd", "update", id_, "--append-notes", text])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox note failed — bd update --append-notes did not succeed for {id_}")
    after = _bd_issue_json_or_backend(runner, id_, f"inbox note failed — {id_} state changed while appending note")
    if status_labels_before != _status_labels(after):
        backend_fail(f"inbox note failed — {id_} state changed while appending note")
    _success(f"noted {id_}", env)
    return 0


def cmd_inbox_update(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk inbox update: missing id — usage: clerk inbox update <id> [--title <title>] [--type <type>] [--body-file <path>|--stdin --body-guard <guard>]")
    id_ = argv[0]
    title = ""
    type_ = ""
    body_file = ""
    guard = ""
    have_body = False
    use_stdin = False
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--title":
            if i + 1 >= len(args):
                usage("clerk inbox update: --title needs a value")
            title = args[i + 1]
            i += 2
        elif arg == "--type":
            if i + 1 >= len(args):
                usage("clerk inbox update: --type needs a value")
            type_ = args[i + 1]
            i += 2
        elif arg == "--body-file":
            if i + 1 >= len(args):
                usage("clerk inbox update: --body-file needs a path")
            if have_body:
                usage("clerk inbox update: choose only one of --stdin or --body-file")
            body_file = args[i + 1]
            have_body = True
            i += 2
        elif arg == "--stdin":
            if have_body:
                usage("clerk inbox update: choose only one of --stdin or --body-file")
            use_stdin = True
            have_body = True
            i += 1
        elif arg == "--body-guard":
            if i + 1 >= len(args):
                usage("clerk inbox update: --body-guard needs a value from clerk inbox show --json")
            guard = args[i + 1]
            i += 2
        else:
            usage(f"clerk inbox update: unknown argument '{arg}'")
    if not title and not type_ and not have_body:
        usage("clerk inbox update: nothing to update")
    if type_ and not _clerk_type_valid(runner, type_):
        usage(f"clerk inbox update: invalid --type '{type_}' — use a canonical core type or configure types.custom")
    if type_ == "impediment":
        _bd_ensure_impediment_type(runner)

    obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox update")
    update_args = ["bd", "update", id_]
    if title:
        update_args.extend(["--title", title])
    if type_:
        update_args.extend(["--type", type_])
    body = ""
    if have_body:
        if not guard:
            usage("clerk inbox update: replacing the body requires --body-guard from clerk inbox show --json")
        current_guard = _body_guard(str(obj.get("updated_at") or ""), str(obj.get("description") or ""))
        if guard != current_guard:
            usage("clerk inbox update: stale body guard — rerun clerk inbox show --json and retry")
        body = _read_stdin_trimmed() if use_stdin else _read_file_trimmed(body_file, "clerk inbox update", body=True)
        update_args.extend(["--description", body, "--allow-empty-description"])
    result = runner.run(update_args)
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox update failed — bd update did not succeed for {id_}")
    after = _bd_issue_json_or_backend(runner, id_, f"inbox update failed — {id_} was not confirmed updated")
    if title and after.get("title") != title:
        backend_fail(f"inbox update failed — {id_} was not confirmed updated")
    if type_ and after.get("issue_type") != type_:
        backend_fail(f"inbox update failed — {id_} was not confirmed updated")
    if have_body and str(after.get("description") or "").rstrip("\n") != body:
        backend_fail(f"inbox update failed — {id_} was not confirmed updated")
    _success(f"updated {id_}", env)
    return 0


def cmd_inbox_ready(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    # The Inbox ready/drop bridge promotes a groomed capture from Refinement to delivery
    # while preserving Acceptance-criteria and returned-attempt safety (ADR 0015/0016).
    if not argv:
        usage("clerk inbox ready: missing id — usage: clerk inbox ready <id> [--design-file <path>] [--acceptance-file <path>]")
    id_ = argv[0]
    title = ""
    body_file = ""
    design_file = ""
    acceptance_file = ""
    returned_disposition = ""
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--title":
            if i + 1 >= len(args):
                usage("clerk inbox ready: --title needs a value")
            title = args[i + 1]
            i += 2
        elif arg == "--body-file":
            if i + 1 >= len(args):
                usage("clerk inbox ready: --body-file needs a value")
            body_file = args[i + 1]
            i += 2
        elif arg == "--design-file":
            if i + 1 >= len(args):
                usage("clerk inbox ready: --design-file needs a path")
            design_file = args[i + 1]
            i += 2
        elif arg == "--acceptance-file":
            if i + 1 >= len(args):
                usage("clerk inbox ready: --acceptance-file needs a path")
            acceptance_file = args[i + 1]
            i += 2
        elif arg == "--returned":
            if i + 1 >= len(args):
                usage("clerk inbox ready: --returned needs keep or discard")
            returned_disposition = args[i + 1]
            i += 2
        else:
            usage(f"clerk inbox ready: unknown argument '{arg}'")

    short = _returned_short_from_id(id_)

    if backend == "bd":
        if title:
            usage("clerk inbox ready: --title is only for gh-backed promotion; use --design-file/--acceptance-file for bd")
        if body_file:
            usage("clerk inbox ready: --body-file is only for gh-backed promotion; use --design-file/--acceptance-file for bd")
        if design_file and not Path(design_file).is_file():
            usage(f"clerk inbox ready: design file not found: {design_file}")
        if acceptance_file and not Path(acceptance_file).is_file():
            usage(f"clerk inbox ready: acceptance file not found: {acceptance_file}")

        obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox ready")
        if not _is_active_inbox(obj):
            usage(f"clerk inbox ready: {id_} must be an open inbox item (not ready/promoted/closed)")
        _planning_holder_refusal("inbox ready", root, obj, runner, env)
        _handle_returned_disposition("inbox ready", root, short, returned_disposition, runner, env)

        if design_file or acceptance_file:
            update_args = ["bd", "update", id_]
            if design_file:
                update_args.extend(["--design-file", design_file])
            if acceptance_file:
                update_args.extend(["--acceptance", _read_file_trimmed(acceptance_file, "clerk inbox ready", body=True)])
            result = runner.run(update_args)
            _emit_stderr(result)
            if result.returncode != 0:
                backend_fail(f"inbox ready failed — bd update did not succeed for {id_}")
            refreshed = _bd_issue_json_or_backend(runner, id_, f"inbox ready failed — {id_} was not confirmed updated")
            if design_file and str(refreshed.get("design") or "").rstrip("\n") != _read_file_trimmed(design_file, "clerk inbox ready"):
                backend_fail(f"inbox ready failed — design was not confirmed after writing {design_file}")
            if acceptance_file and str(refreshed.get("acceptance_criteria") or "").rstrip("\n") != _read_file_trimmed(acceptance_file, "clerk inbox ready"):
                backend_fail(f"inbox ready failed — acceptance criteria were not confirmed after writing {acceptance_file}")
            obj = refreshed

        # C-e: bd's first-class `acceptance_criteria` field IS the structural section by
        # construction, so its mere non-empty presence satisfies the gate without rescanning;
        # otherwise description+design prose is scanned for a heading or bare line.
        desc = str(obj.get("description") or "")
        design = str(obj.get("design") or "")
        ac = str(obj.get("acceptance_criteria") or "")
        if not ac.strip() and not has_acceptance_criteria_section(f"{desc}\n{design}"):
            usage(f"clerk inbox ready: {id_} has no 'Acceptance Criteria' section — rerun with --acceptance-file <path> (and optionally --design-file <path>) before promoting it")

        result = runner.run(["bd", "update", id_, "--status", "open", "--assignee", "", "--add-label", "stage:ready"])
        _emit_stderr(result)
        if result.returncode != 0:
            backend_fail(f"inbox ready failed — bd update did not succeed for {id_}")
        after = _bd_issue_json_or_backend(runner, id_, f"inbox ready failed — {id_} was not confirmed stage:ready after promotion")
        if "stage:ready" not in (after.get("labels") or []):
            backend_fail(f"inbox ready failed — {id_} was not confirmed stage:ready after promotion")
        _success(f"promoted {id_} to stage:ready", env)
        return 0

    # gh-backed promotion: create a ready GitHub issue, then close the bd capture as promoted.
    if design_file:
        usage("clerk inbox ready: --design-file is only for bd-backed promotion; use --title/--body-file for gh")
    if acceptance_file:
        usage("clerk inbox ready: --acceptance-file is only for bd-backed promotion; use --title/--body-file for gh")
    if not title or not body_file:
        usage('clerk inbox ready: gh backend needs both --title "<title>" and --body-file <file> — rerun as \'clerk inbox ready <id> --title "<title>" --body-file <file>\'')
    if not Path(body_file).is_file():
        usage(f"clerk inbox ready: body file not found: {body_file}")

    obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox ready")
    if not _is_active_inbox(obj):
        usage(f"clerk inbox ready: {id_} must be an open inbox item (not ready/promoted/closed)")
    _planning_holder_refusal("inbox ready", root, obj, runner, env)
    _handle_returned_disposition("inbox ready", root, short, returned_disposition, runner, env)

    create_result = runner.run(["gh", "issue", "create", "--title", title, "--body-file", body_file, "--label", "ready-for-agent"])
    _emit_stderr(create_result)
    if create_result.returncode != 0:
        backend_fail("inbox ready failed — gh issue create did not succeed")
    url = create_result.stdout.strip()
    num = url.rsplit("/", 1)[-1]
    close_result = runner.run(["bd", "close", id_, "--reason", f"promoted to GitHub #{num}"])
    _emit_stderr(close_result)
    if close_result.returncode != 0:
        backend_fail(f"inbox ready failed — bd close did not succeed for {id_}")
    after = _bd_issue_json_or_backend(runner, id_, f"inbox ready failed — {id_} was not confirmed closed after promotion")
    if str(after.get("status") or "") != "closed" or str(after.get("close_reason") or "") != f"promoted to GitHub #{num}":
        backend_fail(f"inbox ready failed — {id_} was not confirmed closed after promotion")
    _success(f"promoted {id_} to #{num} ({url})", env)
    return 0


def cmd_inbox_drop(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    # Drop closes an Inbox capture as wontfix for both bd and gh backends. For gh the bd
    # capture is still the raw Inbox store; no GitHub issue exists yet, so gh adds no action.
    if not argv:
        usage("clerk inbox drop: missing id — usage: clerk inbox drop <id> [--returned keep|discard]")
    id_ = argv[0]
    returned_disposition = ""
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--returned":
            if i + 1 >= len(args):
                usage("clerk inbox drop: --returned needs keep or discard")
            returned_disposition = args[i + 1]
            i += 2
        else:
            usage(f"clerk inbox drop: unknown argument '{arg}'")

    if backend not in {"bd", "gh"}:
        backend_fail(f"drop failed — unsupported backend {backend}")

    short = _returned_short_from_id(id_)
    obj = _bd_issue_json_or_usage(runner, id_, "clerk inbox drop")
    _planning_holder_refusal("inbox drop", root, obj, runner, env)
    _handle_returned_disposition("inbox drop", root, short, returned_disposition, runner, env)

    result = runner.run(["bd", "close", id_, "--reason", "wontfix"])
    _emit_stderr(result)
    if result.returncode != 0:
        backend_fail(f"inbox drop failed — bd close did not succeed for {id_}")
    after = _bd_issue_json_or_backend(runner, id_, f"inbox drop failed — {id_} was not confirmed closed")
    if str(after.get("status") or "") != "closed":
        backend_fail(f"inbox drop failed — {id_} was not confirmed closed")
    _success(f"dropped {id_} (wontfix)", env)
    return 0


def _in_job_context(env: Mapping[str, str]) -> bool:
    if env.get("CLERK_JOB"):
        return True
    return env.get("CI", "").lower() not in {"", "0", "false", "no"}


def _fetch_origin(runner: CommandRunner, root: Path, env: Mapping[str, str]) -> bool:
    return runner.run(["git", "-C", str(root), "fetch", "origin"], env={**env, "GIT_TERMINAL_PROMPT": "0"}, timeout=10).returncode == 0


def _ensure_delivery_worktree(runner: CommandRunner, root: Path, short: str) -> Path | None:
    worktree = root / ".worktrees" / short
    if worktree.is_dir():
        return worktree
    _git(runner, root, ["worktree", "prune"])
    if _git(runner, root, ["worktree", "add", str(worktree), f"delivery/{short}"]).returncode == 0:
        return worktree
    if _show_ref(runner, root, f"refs/remotes/origin/delivery/{short}") and _git(
        runner, root, ["worktree", "add", "-b", f"delivery/{short}", str(worktree), f"origin/delivery/{short}"]
    ).returncode == 0:
        return worktree
    return None


def _provision_worktree_beads(adapter: BdWorkGraphAdapter, root: Path, worktree: Path, id_: str) -> bool:
    metadata = worktree / ".beads" / "metadata.json"
    if (worktree / ".beads" / "config.yaml").is_file() and not metadata.is_file():
        source = root / ".beads" / "metadata.json"
        try:
            shutil.copyfile(source, metadata)
        except OSError:
            return False
    try:
        return adapter.inspect_at(id_, str(worktree)).get("id") == id_
    except WorkGraphBackendError:
        return False


def _replay_returned(runner: CommandRunner, root: Path, worktree: Path, short: str, base: str) -> None:
    ref = f"returned/{short}" if _show_ref(runner, root, f"refs/heads/returned/{short}") else f"origin/returned/{short}"
    commits = _git(runner, root, ["rev-list", "--reverse", f"{base}..{ref}"])
    if commits.returncode == 0 and not commits.stdout.strip():
        return
    if _git(runner, worktree, ["cherry-pick", f"{base}..{ref}"]).returncode == 0:
        return
    conflicts = _git(runner, worktree, ["diff", "--name-only", "--diff-filter=U"]).stdout.strip().replace("\n", " ") or "unknown"
    print(f"clerk: claim --from-returned hit conflicts while replaying returned/{short} onto delivery/{short}", file=sys.stderr)
    print(f"       resolve in {worktree}, run git cherry-pick --continue, then clerk backlog submit; conflicted paths: {conflicts}", file=sys.stderr)
    raise ClerkExit(2)


def _gh_backlog_item_or_usage(runner: CommandRunner, id_: str, verb: str) -> dict[str, Any]:
    result = runner.run(["gh", "issue", "view", id_, "--json", "number,title,body,assignees,state"])
    if result.returncode != 0:
        if "not found" in result.stderr.lower():
            usage(f"{verb}: {id_} not found — check the id ('clerk backlog next' shows ready units)")
        backend_fail(f"{verb.removeprefix('clerk ')} failed — gh issue view did not succeed for {id_}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        backend_fail(f"{verb.removeprefix('clerk ')} failed — gh issue view did not return valid JSON for {id_}")
    if not isinstance(value, dict) or not value.get("number"):
        backend_fail(f"{verb.removeprefix('clerk ')} failed — gh issue view did not return an issue object for {id_}")
    assignees = value.get("assignees") or []
    holder = assignees[0].get("login", "") if assignees and isinstance(assignees[0], dict) else ""
    return {"id": str(value["number"]), "title": value.get("title", ""), "description": value.get("body", ""), "status": value.get("state", ""), "assignee": holder}


def _delivery_actor(backend: str, runner: CommandRunner, root: Path, env: Mapping[str, str]) -> str:
    if backend == "bd":
        return _claim_current_actor(runner, root, env)
    result = runner.run(["gh", "api", "user", "--jq", ".login"])
    return result.stdout.strip() if result.returncode == 0 else ""


def _parse_claim_args(argv: Sequence[str]) -> tuple[str, bool, bool, str]:
    if not argv:
        usage("clerk backlog claim: missing id — usage: clerk backlog claim <id>")
    id_ = argv[0]
    replay = fresh = False
    disposition = ""
    args = list(argv[1:])
    i = 0
    while i < len(args):
        if args[i] == "--from-returned":
            replay = True
        elif args[i] == "--fresh":
            fresh = True
        elif args[i] == "--returned":
            if i + 1 == len(args):
                usage("clerk backlog claim: --returned needs keep or discard")
            disposition = args[i + 1]
            i += 1
        else:
            usage(f"clerk backlog claim: unknown argument '{args[i]}' — usage: clerk backlog claim <id> [--from-returned|--fresh --returned keep|discard]")
        i += 1
    if replay and fresh:
        usage("clerk backlog claim: choose only one of --from-returned or --fresh")
    if replay and disposition:
        usage("clerk backlog claim: --returned is only valid with --fresh")
    if not fresh and disposition:
        usage("clerk backlog claim: --returned is only valid with --fresh")
    if disposition not in {"", "keep", "discard"}:
        usage("clerk backlog claim: --returned must be keep or discard")
    return id_, replay, fresh, disposition


def cmd_backlog_claim(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    id_arg, replay, fresh, disposition = _parse_claim_args(argv)
    if backend == "bd":
        item = _bd_issue_json_or_usage(runner, id_arg, "clerk backlog claim", "'clerk backlog next' shows ready units")
    elif backend == "gh":
        item = _gh_backlog_item_or_usage(runner, id_arg, "clerk backlog claim")
    else:
        backend_fail(f"backlog claim failed — unsupported backend {backend}")
    id_ = str(item.get("id") or id_arg)
    short = _returned_short_from_id(id_)
    if not has_acceptance_criteria(item):
        usage(f"clerk backlog claim: {id_} has no 'Acceptance Criteria' section — it needs a grill pass first (e.g. 'clerk inbox pregrill {id_}', then add the section) before it can be claimed")
    adapter = BdWorkGraphAdapter(runner) if backend == "bd" else None
    actor = _delivery_actor(backend, runner, root, env)
    holder = str(item.get("assignee") or "")
    mine = holder == actor and bool(actor) or _show_ref(runner, root, f"refs/heads/delivery/{short}")
    if mine:
        worktree = _ensure_delivery_worktree(runner, root, short)
        if worktree is None:
            backend_fail(f"claim failed — could not provision the worktree at {root}/.worktrees/{short} for delivery/{short}")
        if adapter is not None and not _provision_worktree_beads(adapter, root, worktree, id_):
            backend_fail(f"claim failed — could not provision or verify the worktree at {worktree}")
        _success(f"{id_} already claimed by you — worktree ready", env)
        print(worktree)
        return 0
    if holder:
        _claim_conflict(f"clerk: backlog claim refused — delivery/{short} is already claimed by {holder}\n       wait for {holder} to release or finish it, or pick a different unit ('clerk backlog next')")
    if adapter is not None:
        try:
            graph = adapter.load()
        except WorkGraphBackendError as exc:
            _emit_stderr(exc.result)
            backend_fail("backlog claim failed — could not load the Work graph")
        # A complete Work graph is required for blocker/child pickability.
        work = graph.resolve(id_)
        if work is None:
            usage(f"clerk backlog claim: {id_} not found — check the id ('clerk backlog next' shows ready units)")
        reasons = graph.pickability_reasons(work)
        if reasons:
            usage(f"clerk backlog claim: {id_} is not pickable — {', '.join(reasons)}")
    offline = not _fetch_origin(runner, root, env)
    has_returned = _returned_branch_exists(runner, root, short)
    if replay and not has_returned:
        usage(f"clerk backlog claim: --from-returned requested but returned/{short} was not found")
    if has_returned and not replay and (not fresh or not disposition):
        print(f"clerk backlog claim: returned/{short} exists — choose how to claim", file=sys.stderr)
        print(f"  reuse returned work: clerk backlog claim {id_} --from-returned", file=sys.stderr)
        print(f"  start fresh:         clerk backlog claim {id_} --fresh --returned keep|discard", file=sys.stderr)
        raise ClerkExit(2)
    if offline:
        if _in_job_context(env):
            usage(f"clerk: OFFLINE in a job context - refusing {short}: the claim lock needs the remote and no attendant can accept the staleness hazard. Retry when origin is reachable.")
        base = "main"
        if not _show_ref(runner, root, "refs/heads/main"):
            backend_fail(f"claim failed — no local 'main' branch to base delivery/{short} on")
        if _git(runner, root, ["branch", f"delivery/{short}", base]).returncode != 0:
            backend_fail(f"claim failed — could not create local branch delivery/{short} from main")
    else:
        if _show_ref(runner, root, f"refs/remotes/origin/delivery/{short}"):
            _claim_conflict(f"clerk: backlog claim refused — delivery/{short} is already claimed by {holder or 'someone else'}\n       wait for {holder or 'someone else'} to release or finish it, or pick a different unit ('clerk backlog next')")
        base = "origin/main" if _show_ref(runner, root, "refs/remotes/origin/main") else "main"
        base_sha = _git(runner, root, ["rev-parse", base]).stdout.strip()
        if not base_sha:
            backend_fail(f"claim failed — could not resolve a base commit (origin/main or main) for delivery/{short}")
        if _git(runner, root, ["push", "origin", f"{base_sha}:refs/heads/delivery/{short}"]).returncode != 0:
            _fetch_origin(runner, root, env)
            _claim_conflict(f"clerk: backlog claim refused — delivery/{short} was just claimed by {holder or 'someone else'}\n       wait for {holder or 'someone else'} to release or finish it, or pick a different unit ('clerk backlog next')")
        if _git(runner, root, ["branch", f"delivery/{short}", base_sha]).returncode != 0:
            backend_fail(f"claim failed — delivery/{short} is pushed but the local branch could not be created")
        _git(runner, root, ["branch", "--set-upstream-to", f"origin/delivery/{short}", f"delivery/{short}"])
    if adapter is not None:
        claimed = adapter.claim(id_)
        _emit_stderr(claimed)
        if claimed.returncode != 0 or str(_bd_issue_json_or_backend(runner, id_, f"claim failed — delivery/{short} was created but the bd claim did not confirm for {id_}").get("assignee") or "") != actor:
            backend_fail(f"claim failed — delivery/{short} was created but the bd claim did not confirm for {id_}")
    elif actor and runner.run(["gh", "issue", "edit", id_, "--add-assignee", actor]).returncode != 0:
        backend_fail(f"claim failed — delivery/{short} was created but the GitHub claim did not succeed for {id_}")
    worktree = _ensure_delivery_worktree(runner, root, short)
    if worktree is None:
        backend_fail(f"claim failed — could not provision the worktree at {root}/.worktrees/{short} for delivery/{short}")
    if adapter is not None and not _provision_worktree_beads(adapter, root, worktree, id_):
        backend_fail(f"claim failed — could not provision or verify the worktree at {worktree}")
    if replay:
        _replay_returned(runner, root, worktree, short, base)
    elif fresh and disposition == "discard":
        _dispose_returned(runner, root, short, env)
    if offline:
        print(f"clerk: OFFLINE - 'delivery/{short}' claimed LOCALLY ONLY (not pushed). The branch is the lock; it is compare-and-swapped at first reconnect (clerk submit/sync). If another machine claimed {short} meanwhile, that push wins and this local work is discarded. Proceeding, attended.", file=sys.stderr)
    else:
        _success(f"claimed {id_} — delivery/{short} pushed, worktree ready", env)
    print(worktree)
    return 0


def _delivery_ahead_count(runner: CommandRunner, root: Path, short: str) -> int:
    base = "origin/main" if _show_ref(runner, root, "refs/remotes/origin/main") else "main"
    result = _git(runner, root, ["rev-list", "--count", f"{base}..delivery/{short}"])
    try:
        return int(result.stdout.strip())
    except ValueError:
        return 0


def cmd_backlog_release(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage("clerk backlog release: missing id — usage: clerk backlog release <id>")
    if len(argv) > 1:
        usage(f"clerk backlog release: unknown argument '{argv[1]}' — usage: clerk backlog release <id>")
    if backend == "bd":
        item = _bd_issue_json_or_usage(runner, argv[0], "clerk backlog release", "'clerk backlog next' shows ready units")
    elif backend == "gh":
        item = _gh_backlog_item_or_usage(runner, argv[0], "clerk backlog release")
    else:
        backend_fail(f"backlog release failed — unsupported backend {backend}")
    id_, short = str(item.get("id") or argv[0]), _returned_short_from_id(str(item.get("id") or argv[0]))
    main_root = _primary_repo_root(runner, root)
    actor, holder = _delivery_actor(backend, runner, main_root, env), str(item.get("assignee") or "")
    if not ((actor and holder == actor) or _show_ref(runner, main_root, f"refs/heads/delivery/{short}")):
        _success(f"{id_} is not claimed here (no local delivery/{short}) — nothing to release", env)
        return 0
    offline = not _fetch_origin(runner, main_root, env)
    ahead = _delivery_ahead_count(runner, main_root, short)
    if ahead:
        print(f"clerk: backlog release refused — delivery/{short} has {ahead} commit(s) beyond main", file=sys.stderr)
        print(f"       run 'clerk backlog submit {id_}' to save the work, or 'clerk backlog return {id_} --reason \"<text>\"' to abandon it", file=sys.stderr)
        raise ClerkExit(2)
    if offline and _in_job_context(env):
        usage(f"clerk: OFFLINE in a job context - refusing to release {short}: the remote teardown needs origin and no attendant can accept the staleness hazard. Retry when origin is reachable.")
    # The caller may be inside this disposable linked worktree; leave it before removal.
    os.chdir(main_root)
    worktree = main_root / ".worktrees" / short
    if worktree.is_dir() and _git(runner, main_root, ["worktree", "remove", str(worktree)]).returncode != 0:
        backend_fail(f"release failed — could not remove the worktree at {worktree} (commit or stash local changes first)")
    if not worktree.is_dir():
        _git(runner, main_root, ["worktree", "prune"])
    if not offline and _show_ref(runner, main_root, f"refs/remotes/origin/delivery/{short}") and _git(runner, main_root, ["push", "origin", "--delete", f"delivery/{short}"]).returncode != 0:
        backend_fail(f"release failed — could not delete origin delivery/{short}")
    if _show_ref(runner, main_root, f"refs/heads/delivery/{short}") and _git(runner, main_root, ["branch", "-D", f"delivery/{short}"]).returncode != 0:
        backend_fail(f"release failed — could not delete local branch delivery/{short}")
    if backend == "bd":
        adapter = BdWorkGraphAdapter(runner)
        result = adapter.release(id_)
        if result.returncode != 0:
            backend_fail(f"release failed — bd update did not succeed for {id_}")
        after = _bd_issue_json_or_backend(runner, id_, f"release failed — {id_} was not confirmed open/unassigned after release")
        if after.get("status") != "open" or after.get("assignee"):
            backend_fail(f"release failed — {id_} was not confirmed open/unassigned after release")
    elif actor and runner.run(["gh", "issue", "edit", id_, "--remove-assignee", actor]).returncode != 0:
        backend_fail(f"release failed — could not remove the GitHub claim for {id_}")
    if offline:
        print(f"clerk: OFFLINE - delivery/{short} deleted locally only; the remote branch delete is deferred to sync (clerk claim/sync will finish it at the next reconnect).", file=sys.stderr)
    _success(f"released {id_} — delivery/{short} torn down, unit reopened (stage:ready kept)", env)
    return 0


def _archive_returned(runner: CommandRunner, root: Path, short: str, offline: bool) -> None:
    branch, remote = f"returned/{short}", f"refs/remotes/origin/returned/{short}"
    if not _show_ref(runner, root, f"refs/heads/{branch}"):
        if not _show_ref(runner, root, remote):
            return
        if _git(runner, root, ["branch", branch, f"origin/{branch}"]).returncode != 0:
            backend_fail(f"return failed — could not materialize origin/{branch} for archiving")
    suffix = _git(runner, root, ["rev-parse", "--short", branch]).stdout.strip()
    archive = f"{branch}-{suffix}"
    if _git(runner, root, ["branch", "-M", branch, archive]).returncode != 0:
        backend_fail(f"return failed — could not archive {branch} as {archive}")
    if not offline:
        if _git(runner, root, ["push", "origin", archive]).returncode != 0:
            backend_fail(f"return failed — could not push {archive} to origin")
        if _show_ref(runner, root, remote) and _git(runner, root, ["push", "origin", "--delete", branch]).returncode != 0:
            backend_fail(f"return failed — could not delete origin {branch} before replacing it")


def cmd_backlog_return(backend: str, root: Path, argv: Sequence[str], runner: CommandRunner, env: Mapping[str, str]) -> int:
    if not argv:
        usage('clerk backlog return: missing id — usage: clerk backlog return <id> --reason "<text>"')
    id_arg, reason = argv[0], ""
    args, i = list(argv[1:]), 0
    while i < len(args):
        if args[i] != "--reason":
            usage(f"clerk backlog return: unknown argument '{args[i]}' — usage: clerk backlog return <id> --reason \"<text>\"")
        if i + 1 == len(args):
            usage("clerk backlog return: --reason needs a value")
        reason = args[i + 1]
        i += 2
    if not reason:
        usage(f"clerk backlog return: missing --reason — usage: clerk backlog return {id_arg} --reason \"<text>\"")
    if backend == "bd":
        item = _bd_issue_json_or_usage(runner, id_arg, "clerk backlog return", "'clerk backlog next' shows ready units")
    elif backend == "gh":
        item = _gh_backlog_item_or_usage(runner, id_arg, "clerk backlog return")
    else:
        backend_fail(f"backlog return failed — unsupported backend {backend}")
    id_ = str(item.get("id") or id_arg)
    short, main_root = _returned_short_from_id(id_), _primary_repo_root(runner, root)
    if not _show_ref(runner, main_root, f"refs/heads/delivery/{short}"):
        usage(f"clerk backlog return: no local delivery/{short} — claim it first ('clerk backlog claim {id_}')")
    offline = not _fetch_origin(runner, main_root, env)
    if offline and _in_job_context(env):
        usage(f"clerk: OFFLINE in a job context - refusing to return {short}: preserving the branch needs origin and no attendant can accept the staleness hazard. Retry when origin is reachable.")
    sha = _git(runner, main_root, ["rev-parse", f"delivery/{short}"]).stdout.strip()
    # The caller may be inside this disposable linked worktree. Leave it before
    # removal so subsequent backend commands never inherit a deleted cwd.
    os.chdir(main_root)
    worktree = main_root / ".worktrees" / short
    if worktree.is_dir() and _git(runner, main_root, ["worktree", "remove", str(worktree)]).returncode != 0:
        backend_fail(f"return failed — could not remove the worktree at {worktree} (commit or stash local changes first)")
    if not worktree.is_dir():
        _git(runner, main_root, ["worktree", "prune"])
    _archive_returned(runner, main_root, short, offline)
    if _git(runner, main_root, ["branch", "-m", f"delivery/{short}", f"returned/{short}"]).returncode != 0:
        backend_fail(f"return failed — could not rename delivery/{short} to returned/{short}")
    if not offline:
        if _git(runner, main_root, ["push", "origin", f"returned/{short}"]).returncode != 0:
            backend_fail(f"return failed — could not push returned/{short} to origin")
        if _show_ref(runner, main_root, f"refs/remotes/origin/delivery/{short}") and _git(runner, main_root, ["push", "origin", "--delete", f"delivery/{short}"]).returncode != 0:
            backend_fail(f"return failed — could not delete origin delivery/{short}")
    body = f"{reason}\n\nreturned from delivery of {id_}\nevidence: returned/{short} @ {sha}"
    if backend == "bd":
        adapter = BdWorkGraphAdapter(runner)
        result = adapter.return_to_inbox(id_)
        if result.returncode != 0:
            backend_fail(f"return failed — bd update did not succeed for {id_}")
        after = _bd_issue_json_or_backend(runner, id_, f"return failed — {id_} was not confirmed open/not-ready after return")
        if after.get("status") != "open" or "stage:ready" in (after.get("labels") or []):
            backend_fail(f"return failed — {id_} was not confirmed open/not-ready after return")
        _bd_ensure_impediment_type(runner)
        capture = adapter.create_impediment(f"backlog return: {id_}", body)
        if capture.returncode != 0 or not capture.stdout.strip():
            backend_fail(f"return failed — could not file the reason capture for {id_}")
        capture_id = capture.stdout.strip()
        _bd_issue_json_or_backend(runner, capture_id, f"return failed — reason capture {capture_id} was not confirmed after filing")
    else:
        if runner.run(["gh", "issue", "reopen", id_]).returncode != 0 or runner.run(["gh", "issue", "edit", id_, "--remove-label", "ready-for-agent"]).returncode != 0:
            backend_fail(f"return failed — could not reopen {id_} as a GitHub backlog item")
        actor = _delivery_actor("gh", runner, main_root, env)
        if actor and runner.run(["gh", "issue", "edit", id_, "--remove-assignee", actor]).returncode != 0:
            backend_fail(f"return failed — could not remove the GitHub claim for {id_}")
        capture = runner.run(["gh", "issue", "create", "--title", f"backlog return: {id_}", "--body", body, "--label", "type:impediment"])
        if capture.returncode != 0 or not capture.stdout.strip():
            backend_fail(f"return failed — could not file the reason capture for {id_}")
        capture_id = capture.stdout.strip()
    if offline:
        print(f"clerk: OFFLINE - returned/{short} created locally only; pushing it and deleting delivery/{short} on origin is deferred to sync (clerk claim/sync will finish it at the next reconnect).", file=sys.stderr)
    _success(f"returned {id_} — returned/{short} preserved, reopened, reason filed as {capture_id}", env)
    return 0


MUTATION_HANDLERS = {
    ("capture",): cmd_capture,
    ("inbox", "pregrill"): cmd_inbox_pregrill,
    ("inbox", "ready"): cmd_inbox_ready,
    ("inbox", "drop"): cmd_inbox_drop,
    ("inbox", "parent"): cmd_inbox_parent,
    ("inbox", "dep"): cmd_inbox_dep,
    ("inbox", "claim"): cmd_inbox_claim,
    ("inbox", "release"): cmd_inbox_release,
    ("inbox", "note"): cmd_inbox_note,
    ("inbox", "update"): cmd_inbox_update,
    ("inbox", "resolve"): cmd_inbox_resolve,
    ("backlog", "resolve"): cmd_backlog_resolve,
    ("backlog", "claim"): cmd_backlog_claim,
    ("backlog", "release"): cmd_backlog_release,
    ("backlog", "return"): cmd_backlog_return,
}


QUERY_HANDLERS = {
    ("inbox", "list"): cmd_inbox_list,
    ("inbox", "show"): cmd_inbox_show,
    ("inbox", "dups"): cmd_inbox_dups,
    ("inbox", "children"): cmd_inbox_children,
    ("inbox", "frontier"): cmd_inbox_frontier,
    ("inbox", "blockers"): cmd_inbox_blockers,
    ("inbox", "blocked"): cmd_inbox_blocked,
    ("backlog", "next"): cmd_backlog_next,
    ("backlog", "waiting"): cmd_backlog_waiting,
    ("backlog", "show"): cmd_backlog_show,
}


def run_query(path: tuple[str, ...], backend: str, root: Path, argv: Sequence[str], env: Mapping[str, str] = os.environ, runner: CommandRunner | None = None) -> int:
    handler = QUERY_HANDLERS[path]
    try:
        return handler(backend, root, argv, runner or CommandRunner(), env)
    except ClerkExit as exc:
        return exc.code


def run_mutation(path: tuple[str, ...], backend: str, root: Path, argv: Sequence[str], env: Mapping[str, str] = os.environ, runner: CommandRunner | None = None) -> int:
    handler = MUTATION_HANDLERS[path]
    try:
        return handler(backend, root, argv, runner or CommandRunner(), env)
    except ClerkExit as exc:
        return exc.code
