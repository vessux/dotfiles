import contextlib
import hashlib
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


def fail(args, stderr="boom"):
    return CommandResult(tuple(args), 1, "", stderr)


class TextMutationTests(unittest.TestCase):
    def invoke(self, path, argv, responses, *, stdin="", backend="bd"):
        runner = FakeRunner(responses)
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err), \
            mock.patch.object(sys, "stdin", io.StringIO(stdin)):
            code = run_mutation(path, backend, Path(td), argv, {}, runner)
        return code, out.getvalue(), err.getvalue(), runner.calls

    def test_capture_files_bd_capture_with_parent_blockers_type_and_stdin_then_self_verifies(self):
        parent = [{"id": "p", "status": "open"}]
        blocker = [{"id": "b", "status": "open", "parent": "p"}]
        created = [{"id": "dotfiles-new"}]
        code, out, err, calls = self.invoke(
            ("capture",),
            ["title", "--stdin", "--type", "bug", "--parent", "p", "--blocked-by", "b"],
            [
                lambda args: ok(args, json.dumps(parent)),
                lambda args: ok(args, json.dumps(blocker)),
                lambda args: ok(args, "dotfiles-new\n"),
                lambda args: ok(args, json.dumps(created)),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: filed dotfiles-new\n")
        self.assertEqual(err, "")
        self.assertEqual(calls, [
            ["bd", "show", "p", "--readonly", "--json"],
            ["bd", "show", "b", "--readonly", "--json"],
            ["bd", "create", "title", "--silent", "--stdin", "--type", "bug", "--parent", "p", "--deps", "b"],
            ["bd", "show", "dotfiles-new", "--readonly", "--json"],
        ])

    def test_capture_removes_a_ready_label_inherited_from_its_parent_before_success(self):
        parent = [{"id": "p", "status": "open", "labels": ["stage:ready"]}]
        inherited_ready = [{"id": "dotfiles-new", "status": "open", "parent": "p", "labels": ["stage:ready"]}]
        inbox_child = [{"id": "dotfiles-new", "status": "open", "parent": "p", "labels": []}]
        code, out, err, calls = self.invoke(
            ("capture",),
            ["title", "--parent", "p"],
            [
                lambda args: ok(args, json.dumps(parent)),
                lambda args: ok(args, "dotfiles-new\n"),
                lambda args: ok(args, json.dumps(inherited_ready)),
                lambda args: ok(args),
                lambda args: ok(args, json.dumps(inbox_child)),
            ],
        )
        self.assertEqual((code, out, err), (0, "clerk: filed dotfiles-new\n", ""))
        self.assertEqual(calls[-2:], [
            ["bd", "update", "dotfiles-new", "--remove-label", "stage:ready"],
            ["bd", "show", "dotfiles-new", "--readonly", "--json"],
        ])

    def test_capture_failed_self_verification_is_backend_failure_without_success_output(self):
        code, out, err, calls = self.invoke(
            ("capture",),
            ["title"],
            [lambda args: ok(args, "dotfiles-new\n"), lambda args: ok(args, json.dumps([{"id": "other"}]))],
        )
        self.assertEqual(code, 5)
        self.assertEqual(out, "")
        self.assertIn("capture failed — dotfiles-new was not confirmed after creation", err)
        self.assertIn("run 'clerk doctor'", err)
        self.assertEqual(calls[-1], ["bd", "show", "dotfiles-new", "--readonly", "--json"])

    def test_capture_impediment_self_provisions_type_and_reports_type_label(self):
        code, out, err, calls = self.invoke(
            ("capture",),
            ["harness friction", "--impediment"],
            [
                lambda args: ok(args, "types.custom (not set)\n"),
                lambda args: ok(args, ""),
                lambda args: ok(args, "dotfiles-imp\n"),
                lambda args: ok(args, json.dumps([{"id": "dotfiles-imp"}])),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: filed dotfiles-imp (type: impediment)\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[:3], [
            ["bd", "config", "get", "types.custom"],
            ["bd", "config", "set", "types.custom", "impediment"],
            ["bd", "create", "harness friction", "--silent", "--type", "impediment"],
        ])

    def test_inbox_pregrill_appends_structured_note_and_verifies_state_neutrality(self):
        before = [{"id": "item", "status": "open", "labels": ["some-label"]}]
        after = [{"id": "item", "status": "open", "labels": ["some-label"]}]
        code, out, err, calls = self.invoke(
            ("inbox", "pregrill"),
            ["item", "--decision", "which backend", "--premise", "api stable|check changelog", "--criterion", "returns 200"],
            [lambda args: ok(args, json.dumps(before)), lambda args: ok(args), lambda args: ok(args, json.dumps(after))],
        )
        self.assertEqual(code, 0)
        self.assertRegex(out, r"^clerk: pregrilled item \(dated 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\)\n$")
        self.assertEqual(err, "")
        note = calls[1][4]
        self.assertEqual(calls[1][:4], ["bd", "update", "item", "--append-notes"])
        self.assertIn("Open decisions:\n- which backend", note)
        self.assertIn("Premises:\n- api stable (verify: check changelog)", note)
        self.assertIn("Draft acceptance criteria:\n- returns 200", note)

    def test_inbox_note_appends_nonempty_text_and_failed_self_verification_is_backend_failure(self):
        before = [{"id": "item", "status": "open", "labels": []}]
        changed = [{"id": "item", "status": "open", "labels": ["stage:ready"]}]
        code, out, err, calls = self.invoke(
            ("inbox", "note"),
            ["item", "--stdin"],
            [
                lambda args: ok(args, json.dumps(before)),
                lambda args: ok(args, json.dumps(before)),
                lambda args: ok(args),
                lambda args: ok(args, json.dumps(changed)),
            ],
            stdin="plain note\n",
        )
        self.assertEqual(code, 5)
        self.assertEqual(out, "")
        self.assertIn("inbox note failed — item state changed while appending note", err)
        self.assertEqual(calls[2], ["bd", "update", "item", "--append-notes", "plain note"])

    def test_inbox_update_replaces_guarded_body_and_verifies_requested_fields(self):
        before_obj = {"id": "item", "title": "old", "issue_type": "task", "description": "old body", "updated_at": "2026-07-23T01:02:03Z"}
        after_obj = {"id": "item", "title": "new title", "issue_type": "bug", "description": "new body", "updated_at": "2026-07-23T01:03:03Z"}
        guard = hashlib.sha256(b"2026-07-23T01:02:03Z\0old body").hexdigest()
        code, out, err, calls = self.invoke(
            ("inbox", "update"),
            ["item", "--title", "new title", "--type", "bug", "--stdin", "--body-guard", guard],
            [lambda args: ok(args, json.dumps([before_obj])), lambda args: ok(args), lambda args: ok(args, json.dumps([after_obj]))],
            stdin="new body\n",
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: updated item\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[1], ["bd", "update", "item", "--title", "new title", "--type", "bug", "--description", "new body", "--allow-empty-description"])

    def test_inbox_update_failed_self_verification_is_backend_failure(self):
        before_obj = {"id": "item", "description": "old body", "updated_at": "2026-07-23T01:02:03Z"}
        after_obj = {"id": "item", "description": "old body", "updated_at": "2026-07-23T01:03:03Z"}
        guard = hashlib.sha256(b"2026-07-23T01:02:03Z\0old body").hexdigest()
        code, out, err, _ = self.invoke(
            ("inbox", "update"),
            ["item", "--stdin", "--body-guard", guard],
            [lambda args: ok(args, json.dumps([before_obj])), lambda args: ok(args), lambda args: ok(args, json.dumps([after_obj]))],
            stdin="new body",
        )
        self.assertEqual(code, 5)
        self.assertEqual(out, "")
        self.assertIn("inbox update failed — item was not confirmed updated", err)


if __name__ == "__main__":
    unittest.main()
