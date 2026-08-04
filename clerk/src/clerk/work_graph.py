"""Work graph seam and bd-backed adapter.

Clerk command handlers ask this module domain questions.  Beads command shapes,
edge representations, and full-set query details stay inside the adapter.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

from .proc import CommandResult, CommandRunner


class WorkGraphBackendError(Exception):
    """The backing store could not produce a valid Work graph snapshot."""

    def __init__(self, message: str, result: CommandResult) -> None:
        super().__init__(message)
        self.result = result


@dataclass(frozen=True)
class Work:
    id: str
    title: str
    status: str
    labels: tuple[str, ...]
    assignee: str
    parent: str
    raw: dict[str, Any]

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> Work:
        return cls(
            id=str(value.get("id") or ""),
            title=str(value.get("title") or ""),
            status=str(value.get("status") or ""),
            labels=tuple(str(label) for label in value.get("labels") or []),
            assignee=str(value.get("assignee") or ""),
            parent=str(value.get("parent") or ""),
            raw=value,
        )


@dataclass(frozen=True)
class WaitingWork:
    work: Work
    blocker_count: int
    child_count: int


@dataclass(frozen=True)
class Backlog:
    """One consistent view of refinement-complete Work graph state."""

    ready: tuple[Work, ...]
    pickable: tuple[Work, ...]
    waiting: tuple[WaitingWork, ...]


def edge_type(edge: dict[str, Any]) -> str:
    return str(edge.get("dependency_type") or edge.get("type") or "")


def edge_target(edge: dict[str, Any]) -> str:
    return str(edge.get("depends_on_id") or edge.get("id") or "")


def edge_ids(value: dict[str, Any], collection: str, kind: str) -> tuple[str, ...]:
    return tuple(
        edge_target(edge)
        for edge in value.get(collection) or []
        if isinstance(edge, dict) and edge_type(edge) == kind and edge_target(edge)
    )


def has_open_edges(value: dict[str, Any], collection: str, kind: str) -> bool:
    return any(
        isinstance(edge, dict)
        and edge_type(edge) == kind
        and str(edge.get("status") or "open") != "closed"
        for edge in value.get(collection) or []
    )


def is_ready_promoted(value: dict[str, Any]) -> bool:
    return "stage:ready" in (value.get("labels") or []) or str(value.get("close_reason") or "").startswith("promoted")


_ACCEPTANCE_HEADING = re.compile(r"^#{1,6}\s*acceptance criteria|^acceptance criteria:?\s*$", re.IGNORECASE | re.MULTILINE)


def has_acceptance_criteria(value: dict[str, Any]) -> bool:
    if str(value.get("acceptance_criteria") or "").strip():
        return True
    return bool(_ACCEPTANCE_HEADING.search(f"{value.get('description') or ''}\n{value.get('design') or ''}"))


def is_active_inbox(value: dict[str, Any]) -> bool:
    return value.get("status") in {"open", "in_progress"} and "stage:ready" not in (value.get("labels") or [])


def is_open_inbox(value: dict[str, Any]) -> bool:
    return value.get("status") == "open" and "stage:ready" not in (value.get("labels") or [])


def is_nonclosed_work(value: dict[str, Any]) -> bool:
    return bool(value.get("status")) and value.get("status") != "closed"


def parent_id(value: dict[str, Any]) -> str:
    return str(value.get("parent") or "")


def shares_parent(value: dict[str, Any], other: dict[str, Any]) -> bool:
    parent = parent_id(value)
    return bool(parent) and parent == parent_id(other)


def has_blocker(value: dict[str, Any], blocker: str) -> bool:
    return blocker in edge_ids(value, "dependencies", "blocks")


def has_open_blockers(value: dict[str, Any]) -> bool:
    return has_open_edges(value, "dependencies", "blocks")


def has_open_children(value: dict[str, Any]) -> bool:
    return has_open_edges(value, "dependents", "parent-child")


class WorkGraph:
    """Backend-neutral graph snapshot used to answer Clerk domain questions."""

    def __init__(self, items: list[Work]) -> None:
        self.items = tuple(items)
        self._by_id = {item.id: item for item in items}

    def get(self, id_: str) -> Work | None:
        return self._by_id.get(id_)

    def require(self, id_: str) -> Work:
        item = self.get(id_)
        if item is None:
            raise KeyError(id_)
        return item

    def resolve(self, id_: str) -> Work | None:
        item = self.get(id_)
        if item is not None:
            return item
        matches = [candidate for candidate in self.items if candidate.id.split("-", 1)[-1] == id_]
        return matches[0] if len(matches) == 1 else None

    def pickability_reasons(self, item: Work) -> tuple[str, ...]:
        reasons: list[str] = []
        if item.status != "open":
            reasons.append(f"status is {item.status}")
        if "stage:ready" not in item.labels:
            reasons.append("not stage:ready")
        if item.assignee:
            reasons.append(f"claimed by {item.assignee}")
        blockers = self.open_blockers(item)
        children = self.open_children(item)
        if blockers:
            reasons.append(f"{len(blockers)} open blocker(s)")
        if children:
            reasons.append(f"{len(children)} open child(ren)")
        return tuple(reasons)

    def children(self, item: Work) -> tuple[Work, ...]:
        children: list[Work] = []
        seen: set[str] = set()
        for value in item.raw.get("dependents") or []:
            if not isinstance(value, dict) or edge_type(value) != "parent-child":
                continue
            child = self.get(edge_target(value))
            if child is not None and child.id not in seen:
                children.append(child)
                seen.add(child.id)
        for child in self.items:
            if child.parent == item.id and child.id not in seen:
                children.append(child)
                seen.add(child.id)
        return tuple(children)

    def blockers(self, item: Work) -> tuple[Work, ...]:
        result: list[Work] = []
        for value in item.raw.get("dependencies") or []:
            if not isinstance(value, dict) or edge_type(value) != "blocks":
                continue
            target = self.get(edge_target(value))
            if target is not None:
                result.append(target)
        return tuple(result)

    def blocked_by(self, item: Work) -> tuple[Work, ...]:
        return tuple(candidate for candidate in self.items if item.id in {blocker.id for blocker in self.blockers(candidate)})

    def open_blockers(self, item: Work) -> tuple[Work | None, ...]:
        blockers: list[Work | None] = []
        for value in item.raw.get("dependencies") or []:
            if not isinstance(value, dict) or edge_type(value) != "blocks":
                continue
            target = self._by_id.get(edge_target(value))
            edge_status = str(value.get("status") or "")
            if edge_status:
                is_open = edge_status != "closed"
            elif target is not None:
                is_open = target.status != "closed"
            else:
                is_open = True
            if is_open:
                blockers.append(target)
        return tuple(blockers)

    def open_children(self, item: Work) -> tuple[Work, ...]:
        return tuple(child for child in self.children(item) if child.status != "closed")

    def frontier(self, parent: Work) -> tuple[Work, ...]:
        return tuple(
            child
            for child in self.children(parent)
            if child.status == "open"
            and "stage:ready" not in child.labels
            and not child.assignee
            and not self.open_blockers(child)
        )

    def backlog(self) -> Backlog:
        ready = tuple(item for item in self.items if item.status == "open" and "stage:ready" in item.labels)
        unclaimed = tuple(item for item in ready if not item.assignee)
        pickable: list[Work] = []
        waiting: list[WaitingWork] = []
        for item in unclaimed:
            blockers = self.open_blockers(item)
            children = self.open_children(item)
            if blockers or children:
                waiting.append(WaitingWork(item, len(blockers), len(children)))
            elif has_acceptance_criteria(item.raw):
                pickable.append(item)
        return Backlog(ready, tuple(pickable), tuple(waiting))


class BdWorkGraphAdapter:
    """Translate beads primitives into Clerk's Work graph model."""

    def __init__(self, runner: CommandRunner) -> None:
        self._runner = runner

    def load(self) -> WorkGraph:
        result = self._runner.run(["bd", "list", "--all", "--readonly", "--json", "--limit", "0"])
        if result.returncode != 0:
            raise WorkGraphBackendError("bd list did not succeed", result)
        try:
            data = json.loads(result.stdout or "null")
        except json.JSONDecodeError as exc:
            raise WorkGraphBackendError("bd list did not return valid JSON", result) from exc
        if not isinstance(data, list) or any(not isinstance(value, dict) for value in data):
            raise WorkGraphBackendError("bd list did not return a Work list", result)
        return WorkGraph([Work.from_json(value) for value in data])

    def backlog(self) -> Backlog:
        return self.load().backlog()

    def _inspect(self, id_: str, *, cwd: str | None = None) -> dict[str, Any]:
        result = self._runner.run(["bd", "show", id_, "--readonly", "--json"], cwd=cwd)
        if result.returncode != 0:
            raise WorkGraphBackendError(f"bd show did not succeed for {id_}", result)
        try:
            data = json.loads(result.stdout or "null")
        except json.JSONDecodeError as exc:
            raise WorkGraphBackendError(f"bd show did not return valid JSON for {id_}", result) from exc
        if not isinstance(data, list) or not data or not isinstance(data[0], dict):
            raise WorkGraphBackendError(f"bd show did not return a Work item for {id_}", result)
        return data[0]

    def append_notes(self, id_: str, note: str) -> CommandResult:
        return self._runner.run(["bd", "update", id_, "--append-notes", note])

    def close(self, id_: str, reason: str) -> CommandResult:
        return self._runner.run(["bd", "close", id_, "--reason", reason])

    def inspect(self, id_: str) -> dict[str, Any]:
        return self._inspect(id_)

    def inspect_at(self, id_: str, cwd: str) -> dict[str, Any]:
        return self._inspect(id_, cwd=cwd)

    def parent_cycle_would_form(self, child: str, parent: str) -> bool:
        seen: set[str] = set()
        current = parent
        while current:
            if current == child or current in seen:
                return True
            seen.add(current)
            current = str(self._inspect(current).get("parent") or "")
        return False

    def invalid_blockers_for_parent_move(self, child: str, parent: str, child_json: dict[str, Any]) -> tuple[tuple[str, str], ...]:
        invalid: list[tuple[str, str]] = []
        for blocker in edge_ids(child_json, "dependencies", "blocks"):
            other_parent = str(self._inspect(blocker).get("parent") or "")
            if not parent or other_parent != parent:
                invalid.append((child, blocker))
        for dependent in edge_ids(child_json, "dependents", "blocks"):
            other_parent = str(self._inspect(dependent).get("parent") or "")
            if not parent or other_parent != parent:
                invalid.append((dependent, child))
        return tuple(invalid)

    def dependency_path_exists(self, start: str, target: str, seen: set[str] | None = None) -> bool:
        visited = seen or set()
        if start in visited:
            return False
        visited.add(start)
        for blocker in edge_ids(self._inspect(start), "dependencies", "blocks"):
            if blocker == target or self.dependency_path_exists(blocker, target, visited):
                return True
        return False

    def create(self, title: str, *, use_stdin: bool = False, issue_type: str = "", parent: str = "", blockers: tuple[str, ...] = ()) -> CommandResult:
        args = ["bd", "create", title, "--silent"]
        if use_stdin:
            args.append("--stdin")
        if issue_type:
            args.extend(["--type", issue_type])
        if parent:
            args.extend(["--parent", parent])
        for blocker in blockers:
            args.extend(["--deps", blocker])
        return self._runner.run(args)

    def remove_ready_label(self, id_: str) -> CommandResult:
        return self._runner.run(["bd", "update", id_, "--remove-label", "stage:ready"])

    def set_parent(self, child: str, parent: str) -> CommandResult:
        return self._runner.run(["bd", "update", child, "--parent", parent])

    def add_blocker(self, child: str, blocker: str) -> CommandResult:
        return self._runner.run(["bd", "dep", "add", child, blocker])

    def remove_blocker(self, child: str, blocker: str) -> CommandResult:
        return self._runner.run(["bd", "dep", "remove", child, blocker])

    def claim(self, id_: str) -> CommandResult:
        return self._runner.run(["bd", "update", id_, "--claim"])

    def release(self, id_: str) -> CommandResult:
        return self._runner.run(["bd", "update", id_, "--status", "open", "--assignee", ""])

    def return_to_inbox(self, id_: str) -> CommandResult:
        return self._runner.run(["bd", "update", id_, "--status", "open", "--remove-label", "stage:ready", "--assignee", ""])

    def create_impediment(self, title: str, body: str) -> CommandResult:
        return self._runner.run(["bd", "create", title, "--description", body, "--type", "impediment", "--silent"])
