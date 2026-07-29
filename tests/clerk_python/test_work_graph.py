import json
import unittest

from clerk.proc import CommandResult
from clerk.work_graph import BdWorkGraphAdapter


class FakeRunner:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def run(self, args, *, cwd=None, env=None):
        self.calls.append(list(args))
        return CommandResult(tuple(args), 0, json.dumps(self.payload), "")


class BdWorkGraphAdapterTests(unittest.TestCase):
    def test_backlog_distinguishes_ready_pickable_and_waiting_in_one_snapshot(self):
        payload = [
            {"id": "pick", "title": "Pick", "status": "open", "labels": ["stage:ready"], "acceptance_criteria": "- pick"},
            {
                "id": "blocked",
                "title": "Blocked",
                "status": "open",
                "labels": ["stage:ready"],
                "acceptance_criteria": "- blocked",
                "dependencies": [{"type": "blocks", "depends_on_id": "blocker"}],
            },
            {"id": "blocker", "title": "Blocker", "status": "open"},
            {"id": "parent", "title": "Parent", "status": "open", "labels": ["stage:ready"], "acceptance_criteria": "- parent"},
            {"id": "child", "title": "Child", "status": "open", "parent": "parent"},
            {"id": "claimed", "title": "Claimed", "status": "open", "labels": ["stage:ready"], "acceptance_criteria": "- claimed", "assignee": "agent"},
            {"id": "inbox", "title": "Inbox", "status": "open"},
        ]
        runner = FakeRunner(payload)

        backlog = BdWorkGraphAdapter(runner).backlog()

        self.assertEqual([item.id for item in backlog.ready], ["pick", "blocked", "parent", "claimed"])
        self.assertEqual([item.id for item in backlog.pickable], ["pick"])
        self.assertEqual(
            [(item.work.id, item.blocker_count, item.child_count) for item in backlog.waiting],
            [("blocked", 1, 0), ("parent", 0, 1)],
        )
        self.assertEqual(
            runner.calls,
            [["bd", "list", "--all", "--readonly", "--json", "--limit", "0"]],
        )

    def test_graph_queries_and_frontier_share_domain_invariants(self):
        payload = [
            {"id": "parent", "title": "Parent", "status": "open"},
            {"id": "free", "title": "Free", "status": "open", "parent": "parent"},
            {
                "id": "blocked",
                "title": "Blocked",
                "status": "open",
                "parent": "parent",
                "dependencies": [{"type": "blocks", "depends_on_id": "free"}],
            },
            {"id": "claimed", "title": "Claimed", "status": "open", "parent": "parent", "assignee": "agent"},
            {"id": "ready", "title": "Ready", "status": "open", "parent": "parent", "labels": ["stage:ready"]},
        ]

        graph = BdWorkGraphAdapter(FakeRunner(payload)).load()
        parent = graph.require("parent")
        free = graph.require("free")

        self.assertEqual([item.id for item in graph.children(parent)], ["free", "blocked", "claimed", "ready"])
        self.assertEqual([item.id for item in graph.blockers(graph.require("blocked"))], ["free"])
        self.assertEqual([item.id for item in graph.blocked_by(free)], ["blocked"])
        self.assertEqual([item.id for item in graph.frontier(parent)], ["free"])

    def test_closed_children_and_blockers_stop_withholding_a_ready_parent(self):
        payload = [
            {
                "id": "parent",
                "title": "Parent",
                "status": "open",
                "labels": ["stage:ready"],
                "acceptance_criteria": "- parent",
                "dependencies": [{"type": "blocks", "depends_on_id": "blocker"}],
            },
            {"id": "blocker", "title": "Blocker", "status": "closed"},
            {"id": "child", "title": "Child", "status": "closed", "parent": "parent"},
        ]

        backlog = BdWorkGraphAdapter(FakeRunner(payload)).backlog()

        self.assertEqual([item.id for item in backlog.pickable], ["parent"])
        self.assertEqual(backlog.waiting, ())

    def test_backlog_excludes_ready_labels_without_acceptance_criteria(self):
        payload = [
            {"id": "missing", "title": "Missing", "status": "open", "labels": ["stage:ready"]},
            {"id": "valid", "title": "Valid", "status": "open", "labels": ["stage:ready"], "acceptance_criteria": "- valid"},
        ]

        backlog = BdWorkGraphAdapter(FakeRunner(payload)).backlog()

        self.assertEqual([item.id for item in backlog.pickable], ["valid"])


if __name__ == "__main__":
    unittest.main()
