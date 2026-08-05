import json
import unittest

from clerk.proc import CommandResult
from clerk.work_graph import BdWorkGraphAdapter, WorkGraphBackendError


class FakeRunner:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def run(self, args, *, cwd=None, env=None):
        self.calls.append(list(args))
        return CommandResult(tuple(args), 0, json.dumps(self.payload), "")


class DeliveryRunner:
    def __init__(self):
        self.item = {"id": "work-1", "title": "Work", "status": "in_progress", "labels": ["stage:ready"]}
        self.calls = []
        self.push_failures = 0

    def run(self, args, *, cwd=None, env=None):
        self.calls.append(list(args))
        if args[:2] == ["bd", "list"]:
            return CommandResult(tuple(args), 0, json.dumps([self.item]), "")
        if args[:2] == ["bd", "show"]:
            return CommandResult(tuple(args), 0, json.dumps([self.item]), "")
        if args[:3] == ["bd", "dolt", "push"] and self.push_failures:
            self.push_failures -= 1
            return CommandResult(tuple(args), 1, "", "push failed")
        if args[:2] == ["bd", "close"]:
            self.item = {**self.item, "status": "closed", "close_reason": args[-1]}
        elif "--remove-label" in args:
            self.item = {**self.item, "labels": []}
        return CommandResult(tuple(args), 0, "", "")


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

    def test_delivery_reconciliation_uses_adapter_and_is_idempotent(self):
        runner = DeliveryRunner()
        adapter = BdWorkGraphAdapter(runner)

        self.assertEqual([work.id for work in adapter.open_claims()], ["work-1"])
        adapter.finish_delivery("work-1", "delivered: PR #9 merged")
        adapter.finish_delivery("work-1", "delivered: PR #9 merged")

        self.assertEqual(sum(call[:2] == ["bd", "close"] for call in runner.calls), 1)
        self.assertEqual(sum("--remove-label" in call for call in runner.calls), 1)
        self.assertEqual(sum(call[:3] == ["bd", "dolt", "push"] for call in runner.calls), 2)

    def test_delivery_reconciliation_retries_backend_push_after_local_state_changed(self):
        runner = DeliveryRunner()
        runner.push_failures = 1
        adapter = BdWorkGraphAdapter(runner)

        with self.assertRaises(WorkGraphBackendError):
            adapter.finish_delivery("work-1", "delivered: PR #9 merged")
        adapter.finish_delivery("work-1", "delivered: PR #9 merged")

        self.assertEqual(sum(call[:2] == ["bd", "close"] for call in runner.calls), 1)
        self.assertEqual(sum("--remove-label" in call for call in runner.calls), 1)
        self.assertEqual(sum(call[:3] == ["bd", "dolt", "push"] for call in runner.calls), 2)

    def test_backlog_excludes_ready_labels_without_acceptance_criteria(self):
        payload = [
            {"id": "missing", "title": "Missing", "status": "open", "labels": ["stage:ready"]},
            {"id": "waiting", "title": "Waiting", "status": "open", "labels": ["stage:ready"], "dependencies": [{"type": "blocks", "depends_on_id": "blocker"}]},
            {"id": "blocker", "title": "Blocker", "status": "open"},
            {"id": "valid", "title": "Valid", "status": "open", "labels": ["stage:ready"], "acceptance_criteria": "- valid"},
        ]

        backlog = BdWorkGraphAdapter(FakeRunner(payload)).backlog()

        self.assertEqual([item.id for item in backlog.pickable], ["valid"])
        self.assertEqual([(item.work.id, item.blocker_count, item.child_count) for item in backlog.waiting], [("waiting", 1, 0)])


if __name__ == "__main__":
    unittest.main()
