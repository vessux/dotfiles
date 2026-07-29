"""Python-owned Clerk command implementations."""

from __future__ import annotations

import hashlib
import json
import os
import re
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


MUTATION_HANDLERS = {
    ("capture",): cmd_capture,
    ("inbox", "pregrill"): cmd_inbox_pregrill,
    ("inbox", "parent"): cmd_inbox_parent,
    ("inbox", "dep"): cmd_inbox_dep,
    ("inbox", "claim"): cmd_inbox_claim,
    ("inbox", "release"): cmd_inbox_release,
    ("inbox", "note"): cmd_inbox_note,
    ("inbox", "update"): cmd_inbox_update,
    ("inbox", "resolve"): cmd_inbox_resolve,
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
