import unittest
from clerk.ownership import is_python_owned, public_verb_path
from clerk.roster import all_public_verb_paths


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

    def test_read_only_item_queries_are_python_owned(self):
        for argv in (
            ["inbox", "list"],
            ["inbox", "show", "dotfiles-123"],
            ["inbox", "dups"],
            ["inbox", "children", "dotfiles-parent"],
            ["inbox", "frontier", "dotfiles-parent"],
            ["inbox", "blockers", "dotfiles-child"],
            ["inbox", "blocked", "dotfiles-blocker"],
            ["backlog", "next"],
            ["backlog", "show", "dotfiles-123"],
        ):
            with self.subTest(argv=argv):
                self.assertTrue(is_python_owned(argv))

    def test_text_and_graph_mutation_verbs_are_python_owned(self):
        for argv in (
            ["capture", "title"],
            ["inbox", "pregrill", "dotfiles-123"],
            ["inbox", "parent", "set", "dotfiles-child", "dotfiles-parent"],
            ["inbox", "dep", "add", "dotfiles-child", "dotfiles-blocker"],
            ["inbox", "claim", "dotfiles-123"],
            ["inbox", "release", "dotfiles-123"],
            ["inbox", "note", "dotfiles-123"],
            ["inbox", "update", "dotfiles-123"],
            ["inbox", "resolve", "dotfiles-123"],
            ["inbox", "ready", "dotfiles-123"],
            ["inbox", "drop", "dotfiles-123"],
        ):
            with self.subTest(argv=argv):
                self.assertTrue(is_python_owned(argv))

    def test_delivery_claim_lifecycle_is_python_owned(self):
        for argv in (
            ["backlog", "claim", "dotfiles-123"],
            ["backlog", "release", "dotfiles-123"],
            ["backlog", "return", "dotfiles-123", "--reason", "blocked"],
        ):
            with self.subTest(argv=argv):
                self.assertTrue(is_python_owned(argv))

    def test_delivery_reconciliation_is_python_owned(self):
        self.assertTrue(is_python_owned(["backlog", "finish", "dotfiles-123"]))
        self.assertTrue(is_python_owned(["sync"]))

    def test_glean_is_python_owned(self):
        self.assertTrue(is_python_owned(["glean"]))

    def test_all_public_verb_paths_are_python_owned(self):
        for path in all_public_verb_paths():
            with self.subTest(path=path):
                self.assertTrue(is_python_owned(path))

    def test_public_verb_path_identifies_roster_paths_without_validating_args(self):
        self.assertEqual(public_verb_path(["backlog", "claim", "dotfiles-123"]), ("backlog", "claim"))
        self.assertEqual(public_verb_path(["--explain", "inbox", "ready"]), ("inbox", "ready"))
        self.assertEqual(public_verb_path(["frobnicate"]), None)


if __name__ == "__main__":
    unittest.main()
