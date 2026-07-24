import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from clerk.commands import run_mutation
from clerk.proc import CommandResult


class FakeRunner:
    def __init__(self, responses=None):
        self.responses = list(responses or [])
        self.calls = []

    def run(self, args, *, cwd=None, env=None):
        self.calls.append(list(args))
        if not self.responses:
            return CommandResult(tuple(args), 0, "", "")
        value = self.responses.pop(0)
        if callable(value):
            return value(args)
        return value


def ok(args, stdout="", stderr=""):
    return CommandResult(tuple(args), 0, stdout, stderr)


def issue(**overrides):
    obj = {
        "id": "item",
        "title": "Item",
        "status": "open",
        "labels": [],
        "assignee": "",
        "parent": None,
        "dependencies": [],
        "dependents": [],
    }
    obj.update(overrides)
    return json.dumps([obj])


class GraphMutationTests(unittest.TestCase):
    def invoke(self, path, argv, responses, *, stdin="", env=None):
        runner = FakeRunner(responses)
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err), \
            mock.patch.object(sys, "stdin", io.StringIO(stdin)):
            code = run_mutation(path, "bd", Path(td), argv, env or {}, runner)
        return code, out.getvalue(), err.getvalue(), runner.calls

    def test_parent_set_self_verifies_before_success(self):
        code, out, err, calls = self.invoke(
            ("inbox", "parent"),
            ["set", "child", "parent"],
            [
                lambda args: ok(args, issue(id="child")),
                lambda args: ok(args, issue(id="parent")),
                lambda args: ok(args, issue(id="parent")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="child", parent="parent")),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: parent set child -> parent\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[-2:], [
            ["bd", "update", "child", "--parent", "parent"],
            ["bd", "show", "child", "--readonly", "--json"],
        ])

    def test_parent_move_refuses_invalid_dependency_edges_without_drop_flag(self):
        child = issue(id="child", parent="p1", dependencies=[{"dependency_type": "blocks", "id": "blocker"}])
        code, out, err, calls = self.invoke(
            ("inbox", "parent"),
            ["set", "child", "p2"],
            [
                lambda args: ok(args, child),
                lambda args: ok(args, issue(id="p2")),
                lambda args: ok(args, issue(id="p2")),
                lambda args: ok(args, issue(id="blocker", parent="p1")),
            ],
        )
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("--drop-invalid-deps", err)
        self.assertNotIn(["bd", "update", "child", "--parent", "p2"], calls)

    def test_parent_set_with_drop_self_verifies_removed_invalid_edges(self):
        child_before = issue(
            id="child",
            parent="p1",
            dependencies=[{"dependency_type": "blocks", "id": "blocker"}],
            dependents=[{"dependency_type": "blocks", "id": "blocked"}],
        )
        code, out, err, calls = self.invoke(
            ("inbox", "parent"),
            ["set", "child", "p2", "--drop-invalid-deps"],
            [
                lambda args: ok(args, child_before),
                lambda args: ok(args, issue(id="p2")),
                lambda args: ok(args, issue(id="p2")),
                lambda args: ok(args, issue(id="blocker", parent="p1")),
                lambda args: ok(args, issue(id="blocked", parent="p1")),
                lambda args: ok(args),
                lambda args: ok(args),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="child", parent="p2", dependencies=[])),
                lambda args: ok(args, issue(id="blocked", dependencies=[])),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: parent set child -> p2\n")
        self.assertEqual(err, "")
        self.assertIn(["bd", "dep", "remove", "child", "blocker"], calls)
        self.assertIn(["bd", "dep", "remove", "blocked", "child"], calls)
        self.assertEqual(calls[-2:], [
            ["bd", "show", "child", "--readonly", "--json"],
            ["bd", "show", "blocked", "--readonly", "--json"],
        ])

    def test_dependency_add_is_sibling_only_cycle_checked_and_self_verified(self):
        code, out, err, calls = self.invoke(
            ("inbox", "dep"),
            ["add", "child", "blocker"],
            [
                lambda args: ok(args, issue(id="child", parent="parent")),
                lambda args: ok(args, issue(id="blocker", parent="parent")),
                lambda args: ok(args, issue(id="blocker")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="child", parent="parent", dependencies=[{"dependency_type": "blocks", "id": "blocker"}])),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: dependency added child blocked-by blocker\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[-2:], [
            ["bd", "dep", "add", "child", "blocker"],
            ["bd", "show", "child", "--readonly", "--json"],
        ])

        code, out, err, _ = self.invoke(
            ("inbox", "dep"),
            ["add", "child", "outsider"],
            [
                lambda args: ok(args, issue(id="child", parent="parent")),
                lambda args: ok(args, issue(id="outsider", parent="other")),
            ],
        )
        self.assertEqual(code, 2)
        self.assertIn("sibling-only", err)

        code, out, err, _ = self.invoke(
            ("inbox", "dep"),
            ["add", "child", "blocker"],
            [
                lambda args: ok(args, issue(id="child", parent="parent")),
                lambda args: ok(args, issue(id="blocker", parent="parent")),
                lambda args: ok(args, issue(id="blocker", dependencies=[{"dependency_type": "blocks", "id": "child"}])),
            ],
        )
        self.assertEqual(code, 2)
        self.assertIn("dependency cycle", err)

    def test_claim_refuses_blocked_item_and_claims_unblocked_item_with_actor_verification(self):
        blocked = issue(id="blocked", dependencies=[{"dependency_type": "blocks", "id": "blocker", "status": "open"}])
        code, out, err, calls = self.invoke(("inbox", "claim"), ["blocked"], [lambda args: ok(args, blocked)])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("open blockers", err)
        self.assertEqual(calls, [["bd", "show", "blocked", "--readonly", "--json"]])

        code, out, err, calls = self.invoke(
            ("inbox", "claim"),
            ["leaf"],
            [
                lambda args: ok(args, issue(id="leaf")),
                lambda args: ok(args, "Planner\n"),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="leaf", assignee="Planner")),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: claimed leaf\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[1], ["git", "-C", calls[1][2], "config", "user.name"])
        self.assertEqual(calls[-2:], [
            ["bd", "update", "leaf", "--claim"],
            ["bd", "show", "leaf", "--readonly", "--json"],
        ])

    def test_release_refuses_other_holder_and_self_verifies_unclaim(self):
        code, out, err, _ = self.invoke(
            ("inbox", "release"),
            ["leaf"],
            [lambda args: ok(args, issue(id="leaf", assignee="Other")), lambda args: ok(args, "Me\n")],
        )
        self.assertEqual(code, 5)
        self.assertIn("claimed by Other", err)
        self.assertNotIn("run 'clerk doctor'", err)

        code, out, err, calls = self.invoke(
            ("inbox", "release"),
            ["leaf"],
            [
                lambda args: ok(args, issue(id="leaf", assignee="Me")),
                lambda args: ok(args, "Me\n"),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="leaf", assignee="")),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: released leaf\n")
        self.assertEqual(calls[-2:], [
            ["bd", "update", "leaf", "--status", "open", "--assignee", ""],
            ["bd", "show", "leaf", "--readonly", "--json"],
        ])

    def test_resolve_appends_resolution_note_closes_and_verifies_closed(self):
        captured = {}
        code, out, err, calls = self.invoke(
            ("inbox", "resolve"),
            ["leaf", "--stdin"],
            [
                lambda args: ok(args, issue(id="leaf")),
                lambda args: captured.__setitem__("note", args[4]) or ok(args),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="leaf", status="closed", notes=captured["note"])),
            ],
            stdin="done\n",
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: resolved leaf\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[1][:4], ["bd", "update", "leaf", "--append-notes"])
        self.assertIn("clerk-resolution:", calls[1][4])
        self.assertIn("\ndone", calls[1][4])
        self.assertEqual(calls[2], ["bd", "close", "leaf", "--reason", "resolved"])

    def test_resolve_refuses_open_blockers(self):
        code, out, err, calls = self.invoke(
            ("inbox", "resolve"),
            ["leaf"],
            [lambda args: ok(args, issue(id="leaf", dependencies=[{"dependency_type": "blocks", "id": "blocker", "status": "open"}]))],
            stdin="done",
        )
        self.assertEqual(code, 2)
        self.assertIn("open blockers", err)
        self.assertEqual(calls, [["bd", "show", "leaf", "--readonly", "--json"]])


if __name__ == "__main__":
    unittest.main()
