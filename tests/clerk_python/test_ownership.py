import unittest
from pathlib import Path

from clerk.legacy import legacy_path
from clerk.ownership import is_python_owned, public_verb_path


class LegacyPathTests(unittest.TestCase):
    def test_direct_module_invocation_finds_the_preserved_shell_script(self):
        self.assertTrue((legacy_path({})).samefile(Path("clerk/legacy/clerk.bash")))


class OwnershipTests(unittest.TestCase):
    def test_python_owns_core_command_boundary_surfaces(self):
        for argv in (
            [],
            ["doctor"],
            ["--version"],
            ["--help"],
            ["--explain", "backlog", "claim"],
            ["--explain", "frobnicate"],
            ["capture", "--help"],
            ["frobnicate"],
        ):
            with self.subTest(argv=argv):
                self.assertTrue(is_python_owned(argv))

    def test_workflow_verb_bodies_still_route_to_legacy_fallback(self):
        for argv in (
            ["capture", "title"],
            ["inbox", "list"],
            ["backlog", "next"],
            ["glean"],
        ):
            with self.subTest(argv=argv):
                self.assertFalse(is_python_owned(argv))

    def test_public_verb_path_identifies_roster_paths_without_validating_args(self):
        self.assertEqual(public_verb_path(["backlog", "claim", "dotfiles-123"]), ("backlog", "claim"))
        self.assertEqual(public_verb_path(["--explain", "inbox", "ready"]), ("inbox", "ready"))
        self.assertEqual(public_verb_path(["frobnicate"]), None)


if __name__ == "__main__":
    unittest.main()
