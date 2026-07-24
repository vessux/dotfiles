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

from .proc import CommandResult, CommandRunner

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


def returned_attempt_banner(runner: CommandRunner, root: Path, short: str, id_: str, dispose_hint: str) -> None:
    main_root = _primary_repo_root(runner, root)
    local_present = _show_ref(runner, main_root, f"refs/heads/returned/{short}")
    remote_present = _show_ref(runner, main_root, f"refs/remotes/origin/returned/{short}")
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
        guard = hashlib.sha256(updated.encode() + b"\0" + guard_body.encode()).hexdigest()
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


def _edge_type(edge: Mapping[str, Any]) -> str:
    return str(edge.get("dependency_type") or edge.get("type") or "")


def _open_blockers(obj: Mapping[str, Any]) -> list[Any]:
    return [edge for edge in obj.get("dependencies") or [] if isinstance(edge, dict) and _edge_type(edge) == "blocks" and (edge.get("status") or "open") != "closed"]


def _open_children(obj: Mapping[str, Any]) -> list[Any]:
    return [edge for edge in obj.get("dependents") or [] if isinstance(edge, dict) and _edge_type(edge) == "parent-child" and (edge.get("status") or "open") != "closed"]


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


def _graph_item(obj: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": obj.get("id"),
        "title": obj.get("title"),
        "status": obj.get("status"),
        "type": obj.get("issue_type"),
        "assignee": obj.get("assignee") or "",
        "labels": obj.get("labels") or [],
        "parent": obj.get("parent") if obj.get("parent") is not None else None,
        "created_at": obj.get("created_at"),
        "updated_at": obj.get("updated_at"),
    }


def _graph_edge_ids(obj: Mapping[str, Any], collection: str, edge_type: str) -> list[str]:
    ids: list[str] = []
    for edge in obj.get(collection) or []:
        if isinstance(edge, dict) and _edge_type(edge) == edge_type and edge.get("id"):
            ids.append(str(edge["id"]))
    return ids


def _bd_graph_issue(runner: CommandRunner, id_: str, kind: str) -> dict[str, Any]:
    return _bd_issue_json_or_usage(runner, id_, f"clerk inbox {kind}")


def _bd_graph_items(runner: CommandRunner, ids: Sequence[str], kind: str) -> list[dict[str, Any]]:
    return [_graph_item(_bd_graph_issue(runner, id_, kind)) for id_ in ids]


def _is_open_inbox(obj: Mapping[str, Any]) -> bool:
    return obj.get("status") == "open" and "stage:ready" not in (obj.get("labels") or [])


def _is_nonclosed_work(obj: Mapping[str, Any]) -> bool:
    return bool(obj.get("status")) and obj.get("status") != "closed"


def _has_open_blocker_edge(obj: Mapping[str, Any]) -> bool:
    return any(
        isinstance(edge, dict) and _edge_type(edge) == "blocks" and (edge.get("status") or "open") != "closed"
        for edge in obj.get("dependencies") or []
    )


def cmd_inbox_children(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("children", argv)
    parent = _bd_graph_issue(runner, id_, "children")
    child_ids = _graph_edge_ids(parent, "dependents", "parent-child")
    rendered = {"parent": _graph_item(parent), "items": _bd_graph_items(runner, child_ids, "children")}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_inbox_blockers(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("blockers", argv)
    item = _bd_graph_issue(runner, id_, "blockers")
    blocker_ids = _graph_edge_ids(item, "dependencies", "blocks")
    rendered = {"item": _graph_item(item), "items": _bd_graph_items(runner, blocker_ids, "blockers")}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_inbox_blocked(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("blocked", argv)
    item = _bd_graph_issue(runner, id_, "blocked")
    blocked_ids = _graph_edge_ids(item, "dependents", "blocks")
    rendered = {"item": _graph_item(item), "items": _bd_graph_items(runner, blocked_ids, "blocked")}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def cmd_inbox_frontier(_backend: str, _root: Path, argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    id_, pretty = _parse_graph_query_args("frontier", argv)
    parent = _bd_graph_issue(runner, id_, "frontier")
    if not _is_nonclosed_work(parent):
        usage(f"clerk inbox frontier: {id_} must be a non-closed Work graph parent")
    items: list[dict[str, Any]] = []
    for child_id in _graph_edge_ids(parent, "dependents", "parent-child"):
        child = _bd_graph_issue(runner, child_id, "frontier")
        if not _is_open_inbox(child):
            continue
        if (child.get("assignee") or "") != "":
            continue
        if _has_open_blocker_edge(child):
            continue
        items.append(_graph_item(child))
    rendered = {"parent": _graph_item(parent), "items": items}
    print(_dump_json(rendered, pretty=pretty), end="")
    return 0


def _ready_unclaimed_details(runner: CommandRunner) -> list[dict[str, Any]]:
    data = _json_from_result(
        runner.run(["bd", "list", "--status", "open", "--label", "stage:ready", "--no-assignee", "--readonly", "--json"]),
        "backlog next failed — bd list/show did not succeed",
    )
    if not isinstance(data, list):
        backend_fail("backlog next failed — bd list did not return an issue list")
    details: list[dict[str, Any]] = []
    for row in data:
        if not isinstance(row, dict) or not row.get("id"):
            backend_fail("backlog next failed — bd list did not return issue ids")
        result = runner.run(["bd", "show", str(row["id"]), "--readonly", "--json"])
        data = _json_from_result(result, "backlog next failed — bd list/show did not succeed")
        if not isinstance(data, list) or not data or not isinstance(data[0], dict):
            backend_fail("backlog next failed — bd list/show did not succeed")
        details.append(data[0])
    return details


def _is_pickable(obj: Mapping[str, Any]) -> bool:
    return (
        obj.get("status") == "open"
        and "stage:ready" in (obj.get("labels") or [])
        and (obj.get("assignee") or "") == ""
        and not _open_blockers(obj)
        and not _open_children(obj)
    )


def cmd_backlog_next(backend: str, _root: Path, _argv: Sequence[str], runner: CommandRunner, _env: Mapping[str, str]) -> int:
    if backend == "bd":
        pickable = [obj for obj in _ready_unclaimed_details(runner) if _is_pickable(obj)]
        print(f"Backlog (ready) — {len(pickable)} item(s):")
        if not pickable:
            print("  (empty)")
            return 0
        for item in pickable:
            print(f"  {item.get('id', '')}  {item.get('title', '')}")
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
        print(f"  #{item.get('number')}  {item.get('title', '')}")
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
