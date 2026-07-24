import contextlib
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from clerk.commands import has_acceptance_criteria_section, run_mutation
from clerk.proc import CommandResult


class FakeRunner:
    def __init__(self, responses=None, *, git_responses=None):
        self.responses = list(responses or [])
        self.git_responses = list(git_responses or [])
        self.calls = []

    def run(self, args, *, cwd=None, env=None):
        self.calls.append(list(args))
        if args and args[0] == "git":
            # Default git answer mirrors a plain temp sandbox: refs absent, config unset.
            # Tests that need a present ref or a known actor supply explicit git_responses.
            if not self.git_responses:
                return fail(args)
            value = self.git_responses.pop(0)
            if callable(value):
                return value(args)
            return value
        if not self.responses:
            return CommandResult(tuple(args), 0, "", "")
        value = self.responses.pop(0)
        if callable(value):
            return value(args)
        return value


def ok(args, stdout="", stderr=""):
    return CommandResult(tuple(args), 0, stdout, stderr)


def fail(args, stdout="", stderr=""):
    return CommandResult(tuple(args), 1, stdout, stderr)


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
        "description": "",
        "design": "",
        "acceptance_criteria": "",
    }
    obj.update(overrides)
    return json.dumps([obj])


class AcceptanceSectionTests(unittest.TestCase):
    def test_markdown_heading_at_any_depth_counts(self):
        for depth in range(1, 7):
            with self.subTest(depth=depth):
                self.assertTrue(has_acceptance_criteria_section(f"{'#' * depth} Acceptance Criteria\n- x"))

    def test_bare_line_counts_with_or_without_colon(self):
        self.assertTrue(has_acceptance_criteria_section("Acceptance Criteria\n- x"))
        self.assertTrue(has_acceptance_criteria_section("Acceptance Criteria:\n- x"))

    def test_prose_merely_mentioning_the_phrase_does_not_count(self):
        self.assertFalse(has_acceptance_criteria_section("no acceptance criteria yet, sorry"))
        self.assertFalse(has_acceptance_criteria_section("we should talk about Acceptance Criteria somewhere"))

    def test_case_insensitive_heading_and_bare_line(self):
        self.assertTrue(has_acceptance_criteria_section("## ACCEPTANCE CRITERIA\n- x"))
        self.assertTrue(has_acceptance_criteria_section("## Acceptance Criteria\n- x"))
        # Heading must start at column 0, per legacy grep '^#{1,6}...': leading spaces do not count.
        self.assertFalse(has_acceptance_criteria_section("  ## acceptance criteria\n- x"))


class ReadyDropTests(unittest.TestCase):
    def invoke(self, path, argv, responses, *, stdin="", env=None, git_responses=None, root_is_temp=True):
        runner = FakeRunner(responses, git_responses=git_responses)
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err), \
            mock.patch.object(sys, "stdin", io.StringIO(stdin)):
            root = Path(td) if root_is_temp else Path("/repo")
            code = run_mutation(path, "bd", root, argv, env or {}, runner)
        return code, out.getvalue(), err.getvalue(), runner.calls

    # --- ready: bd promotion ---

    def test_ready_bd_promotes_with_first_class_criteria_and_self_verifies(self):
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [
                lambda args: ok(args, issue(id="cap1", acceptance_criteria="does the thing")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1", acceptance_criteria="does the thing", labels=["stage:ready"])),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: promoted cap1 to stage:ready\n")
        self.assertEqual(err, "")
        self.assertEqual(calls[-2:], [
            ["bd", "update", "cap1", "--status", "open", "--assignee", "", "--add-label", "stage:ready"],
            ["bd", "show", "cap1", "--readonly", "--json"],
        ])

    def test_ready_bd_promotes_with_criteria_heading_in_design(self):
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [
                lambda args: ok(args, issue(id="cap1", design="Acceptance Criteria\n- does it")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1", design="Acceptance Criteria\n- does it", labels=["stage:ready"])),
            ],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: promoted cap1 to stage:ready\n")

    def test_ready_bd_refuses_missing_acceptance_criteria(self):
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, issue(id="cap1", description="just prose, no heading"))],
        )
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("no 'Acceptance Criteria' section", err)
        self.assertIn("--acceptance-file", err)
        self.assertEqual(calls, [["bd", "show", "cap1", "--readonly", "--json"]])
        # No mutation attempted.
        self.assertNotIn(["bd", "update", "cap1", "--status", "open", "--assignee", "", "--add-label", "stage:ready"], calls)

    def test_ready_bd_refuses_prose_only_criteria(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, issue(id="cap1", description="no acceptance criteria yet, sorry"))],
        )
        self.assertEqual(code, 2)
        self.assertIn("no 'Acceptance Criteria' section", err)

    def test_ready_bd_refuses_open_blockers(self):
        blocked = issue(id="cap1", dependencies=[{"dependency_type": "blocks", "id": "blk1", "status": "open"}])
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, blocked)],
        )
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("open blockers", err)
        self.assertEqual(calls, [["bd", "show", "cap1", "--readonly", "--json"]])

    def test_ready_bd_refuses_open_children(self):
        parentish = issue(id="cap1", dependents=[{"dependency_type": "parent-child", "id": "kid1", "status": "open"}])
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, parentish)],
        )
        self.assertEqual(code, 2)
        self.assertIn("open children", err)
        self.assertEqual(calls, [["bd", "show", "cap1", "--readonly", "--json"]])

    def test_ready_bd_refuses_already_ready_promoted_item(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, issue(id="cap1", labels=["stage:ready"], acceptance_criteria="x"))],
        )
        self.assertEqual(code, 2)
        self.assertIn("must be an open inbox item", err)

    def test_ready_bd_refuses_closed_item(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, issue(id="cap1", status="closed", acceptance_criteria="x"))],
        )
        self.assertEqual(code, 2)
        self.assertIn("must be an open inbox item", err)

    def test_ready_bd_bad_id_is_usage_error_not_acceptance_refusal(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["does-not-exist-42"],
            [lambda args: CommandResult(tuple(args), 1, "", "")],
        )
        self.assertEqual(code, 2)
        self.assertEqual(err[: len("clerk inbox ready")], "clerk inbox ready")
        self.assertIn("not found", err)

    def test_ready_bd_missing_id_is_usage_error(self):
        code, out, err, _ = self.invoke(("inbox", "ready"), [], [])
        self.assertEqual(code, 2)
        self.assertIn("missing id", err)

    def test_ready_bd_unknown_argument(self):
        code, out, err, _ = self.invoke(("inbox", "ready"), ["cap1", "--bogus"], [lambda args: ok(args, issue(id="cap1"))])
        self.assertEqual(code, 2)
        self.assertIn("unknown argument", err)

    def test_ready_bd_rejects_gh_only_flags(self):
        code, out, err, _ = self.invoke(("inbox", "ready"), ["cap1", "--title", "x"], [lambda args: ok(args, issue(id="cap1"))])
        self.assertEqual(code, 2)
        self.assertIn("--title is only for gh-backed", err)
        code, out, err, _ = self.invoke(("inbox", "ready"), ["cap1", "--body-file", "x"], [lambda args: ok(args, issue(id="cap1"))])
        self.assertEqual(code, 2)
        self.assertIn("--body-file is only for gh-backed", err)

    def test_ready_bd_authors_design_and_acceptance_files_then_promotes(self):
        design_text = "Implementation notes from grill\n"
        acceptance_text = "- delivered behavior is observable\n"
        updated_after_write = issue(
            id="cap1",
            design="Implementation notes from grill",  # rstrip'd file content
            acceptance_criteria="- delivered behavior is observable",
        )
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1", "--design-file", "DESIGN", "--acceptance-file", "ACCEPT"],
            [lambda args: ok(args, issue(id="cap1", description="raw capture")),
             lambda args: ok(args),  # bd update --design-file --acceptance
             lambda args: ok(args, updated_after_write),  # re-show to verify write
             lambda args: ok(args),  # bd update --status open --assignee "" --add-label
             lambda args: ok(args, issue(id="cap1", labels=["stage:ready"]))],  # verify promotion
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: promoted cap1 to stage:ready\n")
        self.assertEqual(err, "")
        # The write update carries both --design-file and --acceptance <text> with file content rstrip'd.
        write_call = calls[1]
        self.assertEqual(write_call[:3], ["bd", "update", "cap1"])
        self.assertIn("--design-file", write_call)
        self.assertIn("--acceptance", write_call)
        acc_idx = write_call.index("--acceptance")
        self.assertEqual(write_call[acc_idx + 1], "- delivered behavior is observable")
        self.assertEqual(calls[-2:][0], ["bd", "update", "cap1", "--status", "open", "--assignee", "", "--add-label", "stage:ready"])

    def test_ready_bd_writes_design_but_still_refuses_missing_criteria(self):
        # bd update succeeds, re-show returns design but no acceptance_criteria or section.
        code, out, err, calls = self.invoke(
            ("inbox", "ready"),
            ["cap1", "--design-file", "DESIGN"],
            [lambda args: ok(args, issue(id="cap1", description="raw capture")),
             lambda args: ok(args),  # bd update --design-file
             lambda args: ok(args, issue(id="cap1", design="Design without an exam")),  # re-show
             ],
        )
        self.assertEqual(code, 2)
        self.assertIn("--acceptance-file", err)
        # No stage:ready mutation.
        self.assertNotIn(["bd", "update", "cap1", "--status", "open", "--assignee", "", "--add-label", "stage:ready"], calls)

    def test_ready_bd_promotion_not_self_verified_fails_closed(self):
        # bd update --add-label succeeds but the re-show lacks the label.
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, issue(id="cap1", acceptance_criteria="x")),
             lambda args: ok(args),  # bd update --add-label
             lambda args: ok(args, issue(id="cap1", labels=[]))],  # verify shows no label
        )
        self.assertEqual(code, 5)
        self.assertIn("was not confirmed stage:ready", err)
        self.assertIn("run 'clerk doctor'", err)

    def test_ready_bd_bd_update_write_failure_is_backend_fail(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1", "--design-file", "DESIGN", "--acceptance-file", "ACCEPT"],
            [lambda args: ok(args, issue(id="cap1")),
             lambda args: fail(args)],  # bd update write fails
        )
        self.assertEqual(code, 5)
        self.assertIn("bd update did not succeed", err)

    def test_ready_bd_design_write_not_confirmed_is_backend_fail(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1", "--design-file", "DESIGN"],
            [lambda args: ok(args, issue(id="cap1")),
             lambda args: ok(args),  # bd update --design-file
             lambda args: ok(args, issue(id="cap1", design="WRONG"))],  # design mismatch on re-show
        )
        self.assertEqual(code, 5)
        self.assertIn("design was not confirmed", err)

    def test_ready_bd_acceptance_write_not_confirmed_is_backend_fail(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1", "--design-file", "DESIGN", "--acceptance-file", "ACCEPT"],
            [lambda args: ok(args, issue(id="cap1")),
             lambda args: ok(args),
             lambda args: ok(args, issue(id="cap1", acceptance_criteria="WRONG"))],
        )
        self.assertEqual(code, 5)
        self.assertIn("acceptance criteria were not confirmed", err)

    def test_ready_bd_refuses_other_holder_exit_5(self):
        captured = {}
        promoted = issue(id="cap1", assignee="Other", acceptance_criteria="x")
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, promoted),
             lambda args: captured.__setitem__("any", args) or ok(args, "Planner\n")],
        )
        self.assertEqual(code, 5)
        self.assertIn("claimed by Other", err)
        self.assertNotIn("run 'clerk doctor'", err)

    def test_ready_bd_allows_current_actor_holder(self):
        code, out, err, _ = self.invoke(
            ("inbox", "ready"),
            ["cap1"],
            [lambda args: ok(args, issue(id="cap1", assignee="Planner", acceptance_criteria="x")),
             lambda args: ok(args, "Planner\n"),  # git config user.name
             lambda args: ok(args),  # bd update add-label
             lambda args: ok(args, issue(id="cap1", labels=["stage:ready"]))],
        )
        self.assertEqual(code, 0)
        self.assertEqual(out, "clerk: promoted cap1 to stage:ready\n")

    # --- ready: gh backend ---

    def test_ready_gh_needs_title_and_body_file(self):
        runner = FakeRunner(responses=[lambda args: ok(args, issue(id="cap1", description="raw capture"))])
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "gh", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("--title", err.getvalue())
        self.assertIn("--body-file", err.getvalue())

    def test_ready_gh_creates_issue_and_closes_capture(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1", description="raw capture")),  # bd show
                lambda args: ok(args, "https://github.com/acme/repo/issues/42\n"),  # gh issue create
                lambda args: ok(args),  # bd close --reason "promoted to GitHub #42"
                lambda args: ok(args, issue(id="cap1", status="closed", close_reason="promoted to GitHub #42", description="raw capture")),  # verify
            ],
        )
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "gh", Path(td), ["cap1", "--title", "promoted title", "--body-file", "BODY"],
                                {}, runner)
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "clerk: promoted cap1 to #42 (https://github.com/acme/repo/issues/42)\n")
        self.assertIn(["gh", "issue", "create", "--title", "promoted title", "--body-file", "BODY", "--label", "ready-for-agent"], runner.calls)
        self.assertIn(["bd", "close", "cap1", "--reason", "promoted to GitHub #42"], runner.calls)

    def test_ready_gh_rejects_bd_only_flags(self):
        runner = FakeRunner(responses=[lambda args: ok(args, issue(id="cap1"))])
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "gh", Path(td), ["cap1", "--design-file", "x", "--title", "t", "--body-file", "b"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("is only for gh-backed", err.getvalue())

    # --- returned disposition ---

    def _git_show_ref_absent(self, args):
        return ok(args, "", "")

    def _git_show_ref_present(self, args):
        return ok(args, "present\n", "")

    def test_ready_returned_required_when_branch_exists(self):
        captured = {}
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1-wxyz", acceptance_criteria="x")),
            ],
            git_responses=[
                self._git_show_ref_present,  # returned_branch_exists: local present
            ],
        )
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1-wxyz"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("--returned keep", err.getvalue())
        self.assertIn("--returned discard", err.getvalue())
        # No bd mutation attempted.
        self.assertNotIn(["bd", "update", "cap1-wxyz", "--status", "open", "--assignee", "", "--add-label", "stage:ready"], runner.calls)

    def test_ready_returned_discard_disposes_and_promotes(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1-wxyz", acceptance_criteria="x")),
                lambda args: ok(args),  # bd update add-label
                lambda args: ok(args, issue(id="cap1-wxyz", labels=["stage:ready"])),
            ],
            # git calls: show-ref(local, present), show-ref(remote, present),
            # for-each-ref(local, list), branch -D pure exit, fetch(no-op success-ish handled below),
            # for-each-ref(remote).
            git_responses=[
                lambda args: ok(args, "present\n"),  # returned_branch_exists local
                lambda args: ok(args, "present\n"),  # returned_branch_exists remote
                lambda args: ok(args, "refs/heads/returned/wxyz\n"),  # for-each-ref local canonical
                lambda args: ok(args, "", ""),  # branch -D
                lambda args: fail(args),  # fetch origin -> offline path? No: we want online. Use success.
            ],
        )
        # Replace fetch with success to take online path.
        runner.git_responses[4] = lambda args: ok(args)
        runner.git_responses.append(lambda args: ok(args, "refs/remotes/origin/returned/wxyz\n"))  # for-each-ref remote
        runner.git_responses.append(lambda args: ok(args, "", ""))  # push origin --delete
        runner.git_responses.append(lambda args: ok(args, "", ""))  # update-ref -d
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1-wxyz", "--returned", "discard"], {}, runner)
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "clerk: promoted cap1-wxyz to stage:ready\n")
        self.assertEqual(err.getvalue(), "")

    def test_ready_returned_keep_preserves_and_promotes(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1-wxyz", acceptance_criteria="x")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1-wxyz", labels=["stage:ready"])),
            ],
        )
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1-wxyz", "--returned", "keep"], {}, runner)
        self.assertEqual(code, 0)
        # No git ref operations because keep short-circuits disposition before any git work.
        git_calls = [c for c in runner.calls if c and c[0] == "git"]
        self.assertEqual(git_calls, [])

    def test_ready_returned_bad_value_is_usage_error(self):
        runner = FakeRunner(responses=[lambda args: ok(args, issue(id="cap1", acceptance_criteria="x"))])
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1", "--returned", "preserve"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("keep or discard", err.getvalue())

    def test_ready_returned_discard_noop_when_no_branch(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1", acceptance_criteria="x")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1", labels=["stage:ready"])),
            ],
            git_responses=[
                lambda args: fail(args),  # show-ref local absent
                lambda args: fail(args),  # show-ref remote absent
                # then dispose_returned enumerates and finds nothing -> no branch -D, but still attempts fetch+nothing.
            ],
        )
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1", "--returned", "discard"], {}, runner)
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "clerk: promoted cap1 to stage:ready\n")

    def test_ready_returned_discard_offline_deletes_local_warns_promotes(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1-wxyz", acceptance_criteria="x")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1-wxyz", labels=["stage:ready"])),
            ],
            git_responses=[
                lambda args: ok(args, "present\n"),  # show-ref local present
                lambda args: ok(args, "present\n"),  # show-ref remote present
                lambda args: ok(args, "refs/heads/returned/wxyz\n"),  # for-each-ref local
                lambda args: ok(args, "", ""),  # branch -D
                lambda args: fail(args),  # fetch origin -> offline
            ],
        )
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1-wxyz", "--returned", "discard"], {}, runner)
        self.assertEqual(code, 0)
        self.assertIn("OFFLINE", err.getvalue())
        self.assertIn("deferred to sync", err.getvalue())

    def test_ready_returned_discard_removes_archived_refs(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1-wxyz", acceptance_criteria="x")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1-wxyz", labels=["stage:ready"])),
            ],
            git_responses=[
                lambda args: ok(args, "present\n"),
                lambda args: ok(args, "present\n"),
                lambda args: ok(args, "refs/heads/returned/wxyz\nrefs/heads/returned/wxyz-abc1234\n"),  # local incl archive
                lambda args: ok(args, "", ""),  # branch -D canonical
                lambda args: ok(args, "", ""),  # branch -D archive
                lambda args: fail(args),  # fetch origin -> offline (no remote deletes)
            ],
        )
        with tempfile.TemporaryDirectory() as td:
            code = run_mutation(("inbox", "ready"), "bd", Path(td), ["cap1-wxyz", "--returned", "discard"], {}, runner)
        self.assertEqual(code, 0)

    # --- drop ---

    def test_drop_bd_closes_wontfix_self_verified(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1")),
                lambda args: ok(args),  # bd close --reason wontfix
                lambda args: ok(args, issue(id="cap1", status="closed", close_reason="wontfix")),
            ],
        )
        with tempfile.TemporaryDirectory() as td:
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.calls[-2], ["bd", "close", "cap1", "--reason", "wontfix"])
        self.assertEqual(runner.calls[-1], ["bd", "show", "cap1", "--readonly", "--json"])

    def test_drop_not_verified_closed_is_backend_fail(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1", status="open")),
            ],
        )
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 5)
        self.assertIn("was not confirmed closed", err.getvalue())

    def test_drop_close_failure_is_backend_fail(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1")),
                lambda args: fail(args),  # bd close fails
            ],
        )
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 5)
        self.assertIn("bd close did not succeed", err.getvalue())

    def test_drop_missing_id_is_usage_error(self):
        runner = FakeRunner()
        with tempfile.TemporaryDirectory() as td:
            code = run_mutation(("inbox", "drop"), "bd", Path(td), [], {}, runner)
        self.assertEqual(code, 2)

    def test_drop_bad_id_is_usage_error(self):
        runner = FakeRunner(responses=[lambda args: CommandResult(tuple(args), 1, "", "")])
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["nope-1"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("not found", err.getvalue())

    def test_drop_unknown_argument(self):
        runner = FakeRunner(responses=[lambda args: ok(args, issue(id="cap1"))])
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1", "--bogus"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("unknown argument", err.getvalue())

    def test_drop_returned_required_when_branch_exists(self):
        runner = FakeRunner(
            responses=[lambda args: ok(args, issue(id="cap1-wxyz"))],
            git_responses=[
                lambda args: ok(args, "present\n"),
                lambda args: ok(args, "present\n"),
            ],
        )
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1-wxyz"], {}, runner)
        self.assertEqual(code, 2)
        self.assertIn("--returned keep", err.getvalue())
        self.assertNotIn(["bd", "close", "cap1-wxyz", "--reason", "wontfix"], runner.calls)

    def test_drop_returned_discard_closes_and_disposes(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1-wxyz")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1-wxyz", status="closed", close_reason="wontfix")),
            ],
            git_responses=[
                lambda args: ok(args, "present\n"),
                lambda args: ok(args, "present\n"),
                lambda args: ok(args, "refs/heads/returned/wxyz\n"),
                lambda args: ok(args, "", ""),
                lambda args: ok(args),  # fetch success (online)
                lambda args: ok(args, "refs/remotes/origin/returned/wxyz\n"),
                lambda args: ok(args, "", ""),  # push --delete
                lambda args: ok(args, "", ""),  # update-ref -d
            ],
        )
        out = io.StringIO()
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1-wxyz", "--returned", "discard"], {}, runner)
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "clerk: dropped cap1-wxyz (wontfix)\n")

    def test_drop_other_holder_refused_exit_5(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1", assignee="Other")),
                lambda args: ok(args, "Planner\n"),
            ],
        )
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as td, contextlib.redirect_stderr(err):
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 5)
        self.assertIn("claimed by Other", err.getvalue())
        self.assertNotIn(err.getvalue(), "run 'clerk doctor'")

    def test_drop_allows_current_actor_holder(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1", assignee="Planner")),
                lambda args: ok(args, "Planner\n"),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1", status="closed", close_reason="wontfix")),
            ],
        )
        with tempfile.TemporaryDirectory() as td:
            code = run_mutation(("inbox", "drop"), "bd", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 0)

    def test_drop_gh_closes_bd_only(self):
        runner = FakeRunner(
            responses=[
                lambda args: ok(args, issue(id="cap1")),
                lambda args: ok(args),
                lambda args: ok(args, issue(id="cap1", status="closed", close_reason="wontfix")),
            ],
        )
        with tempfile.TemporaryDirectory() as td:
            code = run_mutation(("inbox", "drop"), "gh", Path(td), ["cap1"], {}, runner)
        self.assertEqual(code, 0)
        # No gh invocation for drop.
        self.assertFalse(any(c[0] == "gh" for c in runner.calls if c))


if __name__ == "__main__":
    unittest.main()
