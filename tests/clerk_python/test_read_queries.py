import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from clerk.commands import run_query
from clerk.proc import CommandResult


class FakeRunner:
    def __init__(self, responses=None):
        self.responses = list(responses or [])
        self.calls = []

    def run(self, args, *, cwd=None, env=None):
        self.calls.append(list(args))
        if not self.responses:
            return CommandResult(tuple(args), 0, "[]", "")
        value = self.responses.pop(0)
        if callable(value):
            return value(args)
        return value


def ok(args, stdout, stderr=""):
    return CommandResult(tuple(args), 0, stdout, stderr)


def fail(args, stderr="boom"):
    return CommandResult(tuple(args), 1, "", stderr)


class QueryCommandTests(unittest.TestCase):
    def invoke(self, path, backend, argv, responses, *, env=None):
        runner = FakeRunner(responses)
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_query(path, backend, Path(td), argv, env or {}, runner)
        return code, out.getvalue(), err.getvalue(), runner.calls

    def test_inbox_list_renders_pregrill_marker_and_uses_readonly_without_mutation(self):
        data = [{
            "id": "dotfiles-abc",
            "title": "raw capture",
            "notes": "clerk-pregrill: 2026-07-23T01:02:03Z",
            "updated_at": "2026-07-23T01:02:04Z",
        }]
        code, out, err, calls = self.invoke(
            ("inbox", "list"), "bd", ["--limit", "0"], [lambda args: ok(args, json.dumps(data))]
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "Inbox (open, not ready) — 1 item(s):\n  dotfiles-abc  [pregrill:present]  raw capture\n")
        self.assertEqual(err, "")
        self.assertEqual(calls, [["bd", "list", "--status", "open", "--exclude-label", "stage:ready", "--readonly", "--json", "--limit", "0"]])
        self.assertNotIn("update", " ".join(calls[0]))

    def test_inbox_show_json_normalizes_fields_and_body_guard(self):
        issue = [{
            "id": "dotfiles-a1",
            "title": "Show me",
            "status": "open",
            "issue_type": "task",
            "description": "body",
            "created_at": "now",
            "updated_at": "later",
        }]
        code, out, err, calls = self.invoke(
            ("inbox", "show"), "bd", ["dotfiles-a1", "--json"], [lambda args: ok(args, json.dumps(issue))]
        )
        self.assertEqual(code, 0)
        rendered = json.loads(out)
        self.assertEqual(rendered["id"], "dotfiles-a1")
        self.assertEqual(rendered["type"], "task")
        self.assertEqual(rendered["assignee"], "")
        self.assertEqual(rendered["labels"], [])
        self.assertEqual(rendered["body"], "body")
        self.assertEqual(err, "")
        self.assertEqual(calls, [["bd", "show", "dotfiles-a1", "--readonly", "--json"]])

    def test_inbox_dups_renders_duplicate_pairs(self):
        payload = {"count": 1, "pairs": [{"issue_a_id": "a", "issue_a_title": "one", "issue_b_id": "b", "issue_b_title": "two", "similarity": 0.75}]}
        code, out, _, calls = self.invoke(
            ("inbox", "dups"), "bd", [], [lambda args: ok(args, json.dumps(payload))]
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, 'Duplicate candidates — 1 pair(s):\n  a "one"  ~  b "two"  (score: 0.75)\n')
        self.assertEqual(calls, [["bd", "find-duplicates", "--readonly", "--json"]])

    def test_inbox_graph_children_blockers_and_blocked_normalize_json(self):
        parent = [{
            "id": "p",
            "title": "Parent",
            "status": "open",
            "issue_type": "epic",
            "dependents": [
                {"dependency_type": "parent-child", "id": "a"},
                {"dependency_type": "blocks", "id": "unrelated"},
            ],
        }]
        child = [{
            "id": "a",
            "title": "A",
            "status": "open",
            "issue_type": "task",
            "labels": ["x"],
            "parent": "p",
            "created_at": "c",
            "updated_at": "u",
        }]
        code, out, err, calls = self.invoke(
            ("inbox", "children"), "bd", ["p"], [lambda args: ok(args, json.dumps(parent)), lambda args: ok(args, json.dumps(child))]
        )
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertEqual(json.loads(out), {
            "parent": {"id": "p", "title": "Parent", "status": "open", "type": "epic", "assignee": "", "labels": [], "parent": None, "created_at": None, "updated_at": None},
            "items": [{"id": "a", "title": "A", "status": "open", "type": "task", "assignee": "", "labels": ["x"], "parent": "p", "created_at": "c", "updated_at": "u"}],
        })
        self.assertEqual(calls, [["bd", "show", "p", "--readonly", "--json"], ["bd", "show", "a", "--readonly", "--json"]])

        blocker = [{"id": "blocker", "title": "Blocker", "status": "open", "issue_type": "task"}]
        blocked = [{"id": "blocked", "title": "Blocked", "status": "open", "issue_type": "task", "dependencies": [{"dependency_type": "blocks", "id": "blocker"}]}]
        code, out, _, calls = self.invoke(
            ("inbox", "blockers"), "bd", ["blocked", "--pretty"], [lambda args: ok(args, json.dumps(blocked)), lambda args: ok(args, json.dumps(blocker))]
        )
        self.assertEqual(code, 0)
        self.assertIn('\n  "items"', out)
        self.assertEqual(json.loads(out)["items"][0]["id"], "blocker")
        self.assertEqual(calls, [["bd", "show", "blocked", "--readonly", "--json"], ["bd", "show", "blocker", "--readonly", "--json"]])

        reverse = [{"id": "blocker", "title": "Blocker", "status": "open", "issue_type": "task", "dependents": [{"dependency_type": "blocks", "id": "blocked"}]}]
        code, out, _, calls = self.invoke(
            ("inbox", "blocked"), "bd", ["blocker"], [lambda args: ok(args, json.dumps(reverse)), lambda args: ok(args, json.dumps(blocked))]
        )
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["items"][0]["id"], "blocked")
        self.assertEqual(calls, [["bd", "show", "blocker", "--readonly", "--json"], ["bd", "show", "blocked", "--readonly", "--json"]])

    def test_inbox_frontier_filters_empty_blocked_claimed_ready_and_closed_graphs(self):
        parent = [{"id": "p", "title": "Parent", "status": "open", "issue_type": "epic", "dependents": [
            {"dependency_type": "parent-child", "id": "free"},
            {"dependency_type": "parent-child", "id": "blocked"},
            {"dependency_type": "parent-child", "id": "claimed"},
            {"dependency_type": "parent-child", "id": "closed"},
            {"dependency_type": "parent-child", "id": "ready"},
            {"dependency_type": "parent-child", "id": "closed_blocker"},
        ]}]
        details = {
            "free": [{"id": "free", "title": "Free", "status": "open", "issue_type": "task", "parent": "p"}],
            "blocked": [{"id": "blocked", "title": "Blocked", "status": "open", "issue_type": "task", "dependencies": [{"dependency_type": "blocks", "id": "free", "status": "open"}]}],
            "claimed": [{"id": "claimed", "title": "Claimed", "status": "open", "issue_type": "task", "assignee": "other"}],
            "closed": [{"id": "closed", "title": "Closed", "status": "closed", "issue_type": "task"}],
            "ready": [{"id": "ready", "title": "Ready", "status": "open", "issue_type": "task", "labels": ["stage:ready"]}],
            "closed_blocker": [{"id": "closed_blocker", "title": "Closed blocker", "status": "open", "issue_type": "task", "dependencies": [{"dependency_type": "blocks", "id": "free", "status": "closed"}]}],
        }

        def response(args):
            if args[2] == "p":
                return ok(args, json.dumps(parent))
            return ok(args, json.dumps(details[args[2]]))

        code, out, _, calls = self.invoke(("inbox", "frontier"), "bd", ["p"], [response] * 7)
        self.assertEqual(code, 0)
        self.assertEqual([item["id"] for item in json.loads(out)["items"]], ["free", "closed_blocker"])
        self.assertTrue(all(call[:3] == ["bd", "show", call[2]] and "--readonly" in call for call in calls))

        empty_parent = [{"id": "empty", "title": "Empty", "status": "open", "issue_type": "epic", "dependents": []}]
        code, out, _, calls = self.invoke(("inbox", "frontier"), "bd", ["empty"], [lambda args: ok(args, json.dumps(empty_parent))])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["items"], [])
        self.assertEqual(calls, [["bd", "show", "empty", "--readonly", "--json"]])

        closed_parent = [{"id": "p", "title": "Parent", "status": "closed", "issue_type": "epic"}]
        code, _, err, _ = self.invoke(("inbox", "frontier"), "bd", ["p"], [lambda args: ok(args, json.dumps(closed_parent))])
        self.assertEqual(code, 2)
        self.assertIn("must be a non-closed Work graph parent", err)

    def test_inbox_graph_usage_not_found_and_backend_failures(self):
        code, _, err, calls = self.invoke(("inbox", "children"), "bd", [], [])
        self.assertEqual(code, 2)
        self.assertIn("missing parent id", err)
        self.assertEqual(calls, [])

        code, _, err, calls = self.invoke(("inbox", "frontier"), "bd", ["p", "--wat"], [])
        self.assertEqual(code, 2)
        self.assertIn("unknown argument '--wat'", err)
        self.assertEqual(calls, [])

        code, _, err, calls = self.invoke(("inbox", "blockers"), "bd", ["missing"], [lambda args: fail(args, "not found")])
        self.assertEqual(code, 2)
        self.assertIn("clerk inbox blockers: missing not found", err)
        self.assertEqual(calls, [["bd", "show", "missing", "--readonly", "--json"]])

        code, _, err, calls = self.invoke(("inbox", "blocked"), "bd", ["item"], [lambda args: ok(args, "not-json")])
        self.assertEqual(code, 5)
        self.assertIn("inbox blocked failed", err)
        self.assertIn("run 'clerk doctor'", err)
        self.assertEqual(calls, [["bd", "show", "item", "--readonly", "--json"]])

    def test_backlog_next_filters_ready_items_with_blockers_children_and_assignees(self):
        rows = [{"id": "pick"}, {"id": "blocked"}, {"id": "parent"}, {"id": "claimed"}]
        details = {
            "pick": [{"id": "pick", "title": "Pick", "status": "open", "labels": ["stage:ready"], "assignee": ""}],
            "blocked": [{"id": "blocked", "title": "Blocked", "status": "open", "labels": ["stage:ready"], "dependencies": [{"dependency_type": "blocks", "status": "open"}]}],
            "parent": [{"id": "parent", "title": "Parent", "status": "open", "labels": ["stage:ready"], "dependents": [{"dependency_type": "parent-child", "status": "open"}]}],
            "claimed": [{"id": "claimed", "title": "Claimed", "status": "open", "labels": ["stage:ready"], "assignee": "me"}],
        }

        def response(args):
            if args[:2] == ["bd", "list"]:
                return ok(args, json.dumps(rows))
            return ok(args, json.dumps(details[args[2]]))

        code, out, _, calls = self.invoke(("backlog", "next"), "bd", [], [response, response, response, response, response])
        self.assertEqual(code, 0)
        self.assertEqual(out, "Backlog (ready) — 1 item(s):\n  pick  Pick\n")
        self.assertEqual(calls[0], ["bd", "list", "--status", "open", "--label", "stage:ready", "--no-assignee", "--readonly", "--json"])
        self.assertTrue(all("--readonly" in call for call in calls))

    def test_backlog_next_gh_lists_ready_for_agent_issues(self):
        payload = [{"number": 9, "title": "do the thing"}]
        code, out, _, calls = self.invoke(
            ("backlog", "next"), "gh", [], [lambda args: ok(args, json.dumps(payload))]
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "Backlog (ready) — 1 item(s):\n  #9  do the thing\n")
        self.assertEqual(calls, [["gh", "issue", "list", "--label", "ready-for-agent", "--json", "number,title"]])

    def test_show_not_found_is_usage_error(self):
        code, _, err, calls = self.invoke(("inbox", "show"), "bd", ["missing"], [lambda args: fail(args, "not found")])
        self.assertEqual(code, 2)
        self.assertIn("clerk inbox show: missing not found", err)
        self.assertEqual(calls, [["bd", "show", "missing", "--readonly", "--json"]])

    def test_usage_and_backend_failures_have_distinct_exit_codes(self):
        code, _, err, calls = self.invoke(("inbox", "list"), "bd", ["--limit", "nope"], [])
        self.assertEqual(code, 2)
        self.assertIn("--limit must be a non-negative integer", err)
        self.assertEqual(calls, [])

        code, _, err, calls = self.invoke(("inbox", "list"), "bd", [], [lambda args: fail(args)])
        self.assertEqual(code, 5)
        self.assertIn("clerk: inbox list failed", err)
        self.assertIn("run 'clerk doctor'", err)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
