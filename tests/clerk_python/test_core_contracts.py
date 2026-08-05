import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from clerk.cli import main
from clerk.manifest import ManifestStatus, read_manifest


class CliBoundaryTests(unittest.TestCase):
    def invoke(self, argv, *, env=None):
        out = io.StringIO()
        err = io.StringIO()
        with mock.patch.dict(os.environ, env or {}, clear=True), \
            contextlib.redirect_stdout(out), \
            contextlib.redirect_stderr(err):
            code = main(argv)
        return code, out.getvalue(), err.getvalue(), []

    def test_no_arguments_prints_public_roster_without_legacy(self):
        code, out, err, calls = self.invoke([])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("clerk: missing verb\nKnown verbs:\n", err)
        self.assertIn("  doctor [--fix --backend bd|gh]\n", err)
        self.assertEqual(calls, [])

    def test_unknown_and_bare_noun_are_usage_errors_not_legacy(self):
        code, _, err, calls = self.invoke(["frobnicate"])
        self.assertEqual(code, 2)
        self.assertIn("clerk: unknown verb 'frobnicate'", err)
        self.assertEqual(calls, [])

        code, _, err, calls = self.invoke(["backlog"])
        self.assertEqual(code, 2)
        self.assertIn("clerk: 'backlog' needs a verb", err)
        self.assertEqual(calls, [])

    def test_version_and_explain_are_python_owned(self):
        code, out, err, calls = self.invoke(["--version"])
        self.assertEqual((code, out, err, calls), (0, "clerk 0.1.0\n", "", []))

        code, out, err, calls = self.invoke(["--explain", "doctor"])
        self.assertEqual(code, 0)
        self.assertIn("clerk doctor — check and provision workflow plumbing", out)
        self.assertIn("reads .clerk", out)
        self.assertEqual(err, "")
        self.assertEqual(calls, [])

    def test_glean_is_python_owned(self):
        seen = []

        def fake_glean(backend, root, remaining):
            seen.append((backend, root.name, remaining))
            return 0

        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["git", "init", "-q", "-b", "main", td], check=True)
            Path(td, ".clerk").write_text("backlog: bd\n")
            cwd = os.getcwd()
            try:
                os.chdir(td)
                with mock.patch("clerk.cli.run_glean", side_effect=fake_glean):
                    result = self.invoke(["glean", "--async"])
            finally:
                os.chdir(cwd)
        self.assertEqual(result, (0, "", "", []))
        self.assertEqual(seen, [("bd", Path(td).name, ["--async"])])

    def test_reconciliation_verbs_are_python_owned(self):
        seen = []

        def fake_reconciliation(path, backend, root, remaining):
            seen.append((path, backend, root.name, remaining))
            return 0

        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["git", "init", "-q", "-b", "main", td], check=True)
            Path(td, ".clerk").write_text("backlog: bd\n")
            cwd = os.getcwd()
            try:
                os.chdir(td)
                with mock.patch("clerk.cli.run_reconciliation", side_effect=fake_reconciliation):
                    sync = self.invoke(["sync"])
                    finish = self.invoke(["backlog", "finish", "dotfiles-123", "--watch"])
            finally:
                os.chdir(cwd)
        self.assertEqual(sync, (0, "", "", []))
        self.assertEqual(finish, (0, "", "", []))
        self.assertEqual(
            seen,
            [
                (("sync",), "bd", Path(td).name, []),
                (("backlog", "finish"), "bd", Path(td).name, ["dotfiles-123", "--watch"]),
            ],
        )

    def test_python_mutation_verb_uses_manifest_context_without_legacy(self):
        seen = []

        def fake_mutation(path, backend, root, remaining):
            seen.append((path, backend, root.name, remaining))
            return 0

        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["git", "init", "-q", "-b", "main", td], check=True)
            Path(td, ".clerk").write_text("backlog: bd\n")
            cwd = os.getcwd()
            try:
                os.chdir(td)
                with mock.patch("clerk.cli.run_mutation", side_effect=fake_mutation):
                    code, out, err, calls = self.invoke(["capture", "title"])
            finally:
                os.chdir(cwd)
        self.assertEqual((code, out, err, calls), (0, "", "", []))
        self.assertEqual(seen, [(("capture",), "bd", Path(td).name, ["title"])])

    def test_python_query_verb_uses_manifest_context_without_legacy(self):
        seen = []

        def fake_query(path, backend, root, remaining):
            seen.append((path, backend, root.name, remaining))
            return 0

        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["git", "init", "-q", "-b", "main", td], check=True)
            Path(td, ".clerk").write_text("backlog: bd\n")
            cwd = os.getcwd()
            try:
                os.chdir(td)
                with mock.patch("clerk.cli.run_query", side_effect=fake_query):
                    code, out, err, calls = self.invoke(["backlog", "show", "dotfiles-123"])
            finally:
                os.chdir(cwd)
        self.assertEqual((code, out, err, calls), (0, "", "", []))
        self.assertEqual(seen, [(("backlog", "show"), "bd", Path(td).name, ["dotfiles-123"])])

    def test_known_workflow_verb_with_bad_manifest_refuses_before_a_handler(self):
        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["git", "init", "-q", "-b", "main", td], check=True)
            cwd = os.getcwd()
            try:
                os.chdir(td)
                code, out, err, calls = self.invoke(["sync"])
            finally:
                os.chdir(cwd)
        self.assertEqual(code, 4)
        self.assertEqual(out, "")
        self.assertIn("missing .clerk marker", err)
        self.assertEqual(calls, [])

    def test_proof_is_python_owned(self):
        seen = []

        def fake_proof(backend, root, remaining, runner):
            seen.append((backend, root.name, remaining))
            return 0

        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["git", "init", "-q", "-b", "main", td], check=True)
            Path(td, ".clerk").write_text("backlog: bd\n")
            cwd = os.getcwd()
            try:
                os.chdir(td)
                with mock.patch("clerk.cli.cmd_backlog_proof", side_effect=fake_proof):
                    result = self.invoke(["backlog", "proof", "dotfiles-123"])
            finally:
                os.chdir(cwd)
        self.assertEqual(result, (0, "", "", []))
        self.assertEqual(seen, [("bd", Path(td).name, ["dotfiles-123"])])


class ManifestParsingTests(unittest.TestCase):
    def test_manifest_accepts_single_commented_directive(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td, ".clerk")
            path.write_text("# comment\n\n  backlog:   gh   # ok\n")
            result = read_manifest(path)
        self.assertEqual(result.status, ManifestStatus.OK)
        self.assertEqual(result.backend, "gh")

    def test_manifest_rejects_missing_invalid_and_ambiguous(self):
        with tempfile.TemporaryDirectory() as td:
            missing = read_manifest(Path(td, ".clerk"))
            self.assertEqual(missing.status, ManifestStatus.MISSING)

            path = Path(td, ".clerk")
            path.write_text("backlog: jira\n")
            invalid = read_manifest(path)
            self.assertEqual(invalid.status, ManifestStatus.INVALID)

            path.write_text("backlog: bd\nbacklog: gh\n")
            ambiguous = read_manifest(path)
            self.assertEqual(ambiguous.status, ManifestStatus.AMBIGUOUS)


if __name__ == "__main__":
    unittest.main()
