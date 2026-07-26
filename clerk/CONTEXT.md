# Clerk — Workflow-verb facade

Clerk is an independently understandable application context. It presents the workflow verbs that
clients use while hiding the backend and delivery mechanics behind that command boundary.

## Language

**Clerk**:
The opaque workflow-verb facade. Clients state a workflow verb and author judgment; Clerk performs
the deterministic mechanism and owns its public CLI contract, manifest, reconciliation, and backend
binding.
_Avoid_: wrapper, dispatcher, helper

**Work**:
One Clerk-managed unit of discovery or delivery. A Work item carries its title, body, Acceptance
criteria when refined, and its place in the Work graph.
_Avoid_: task, ticket, issue

**Work graph**:
The parent/child and sibling-blocking relationships among Work. Graph state determines whether ready
Work is pickable; it is not a backend-specific tracker graph.
_Avoid_: queue, tracker graph

**Inbox**:
Clerk's refinement collection: Work that is not yet ready. Inbox verbs shape, relate, and promote
Work without exposing the backing store.
_Avoid_: tracker inbox

**Backlog**:
Clerk's delivery collection: refinement-complete Work. A Backlog item may be waiting rather than
pickable when graph state has open children or blockers.
_Avoid_: queue

**Work graph adapter**:
The backend binding behind Clerk's verb facade. It translates backend records and edges into Work,
owns ready/pickable/waiting and parent/child invariants, and exposes graph operations to command
handlers without leaking backend command shapes.
_Avoid_: tracker helper, command-handler graph logic

**Claim**:
The atomic acquisition of one pickable Work item for delivery. A Claim creates the canonical delivery
branch/worktree and is distinct from a planning claim or an assignee.
_Avoid_: assignment, lock

**Planning claim**:
A temporary Inbox ownership marker that keeps a planning item out of the Frontier. It has no delivery
branch, worktree, or delivery lifecycle semantics.
_Avoid_: Claim

**Project gate**:
A project-owned validation policy invoked at the delivery handoff. It may be a one-shot command, an
asynchronous service, or a stronger independent verifier; Clerk does not own its tools, models,
prompts, evidence, artifacts, or criterion-to-test policy.
_Avoid_: Clerk gate, delivery-gate

**Project gate adapter**:
The project-owned command boundary that translates Clerk's Gate request to a Project gate. `run` is
required; `status` is required only after a pending run. The minimum adapter is a synchronous
transform shim around a project command.
_Avoid_: plugin, integration

**Project gate configuration**:
Committed project-owned configuration referenced by `.clerk`. Clerk resolves it and the adapter from
trusted default-branch content; its absence fails submission closed.
_Avoid_: Clerk policy

**Gate request**:
One structured stdin document from Clerk to an adapter, carrying Work identity, full Acceptance
criteria, delivery branch/commit/worktree, and Submission ownership.
_Avoid_: adapter arguments

**Gate result**:
One JSON document emitted by an adapter. It has `status`, `summary`, and `assessed_commit`; a pending
result additionally has opaque `run.id`. It is a valid verdict, unlike a non-zero adapter operational
failure.
_Avoid_: tool log

**Submission ownership**:
The selected owner of the post-validation delivery handoff. `clerk` means Clerk hands off the assessed
worktree head after a pass; `project-gate` means the adapter owns refs, push/PR/CI, and lifecycle
reporting.
_Avoid_: mode
