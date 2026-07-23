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
