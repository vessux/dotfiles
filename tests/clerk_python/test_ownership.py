import unittest
from pathlib import Path

from clerk.legacy import legacy_path
from clerk.ownership import is_python_owned, public_verb_path


class LegacyPathTests(unittest.TestCase):
    def test_direct_module_invocation_finds_the_preserved_shell_script(self):
        self.assertTrue((legacy_path({})).samefile(Path("clerk/legacy/clerk.bash")))


class OwnershipTests(unittest.TestCase):
    def test_project_shell_owns_no_public_workflow_paths_yet(self):
        for argv in (
            ["doctor"],
            ["capture", "title"],
            ["inbox", "list"],
            ["backlog", "next"],
            ["glean"],
            ["--explain", "backlog", "claim"],
        ):
            with self.subTest(argv=argv):
                self.assertFalse(is_python_owned(argv))

    def test_public_verb_path_identifies_roster_paths_without_validating_args(self):
        self.assertEqual(public_verb_path(["backlog", "claim", "dotfiles-123"]), ("backlog", "claim"))
        self.assertEqual(public_verb_path(["--explain", "inbox", "ready"]), ("inbox", "ready"))
        self.assertEqual(public_verb_path(["frobnicate"]), None)


if __name__ == "__main__":
    unittest.main()
