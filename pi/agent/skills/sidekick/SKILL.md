---
name: sidekick
description: >-
  Local Sidekick delegation policy backed by pi-subagents. Specialists deliver
  durable work while the driver owns scope and acceptance.
disable-model-invocation: true
---

# sidekick — bounded delegation

Sidekick is this repo's bounded specialist workflow. The maintained
`pi-subagents` package provides orchestration and persistence; specialists own
mechanical work while the driver owns scope, concurrency, acceptance, and
follow-up.

## Driver policy

- Start with one child. Add children only for independent work.
- Give every child one bounded task, relevant paths, constraints, delivery mode,
  and exact gate.
- Shared-tree editors leave a diff and never commit or change branches.
- Worktree editors run the gate, commit only their scoped changes, and return the
  commit SHA plus handoff/patch paths.
- Children never push or merge. A designated integrator may apply an accepted
  delivery and create the final commit after the driver approves it.
- The driver accepts or rejects from bounded summaries and evidence; it does not
  relay routine Git commands or raw Git output.
- Preserve unrelated work. Reject unexplained edits and unsupported claims.

Every editing prompt includes:

```text
Task: <bounded task>
Scope: <paths and constraints>
Delivery: <shared-tree diff | worktree commit>
Gate: run `<exact command>` before reporting.
Never push or merge; preserve unrelated work.
Return: summary, changed paths, gate result, unfinished work, and for worktrees
        the commit SHA plus handoff/patch paths.
```

## Isolation and concurrency

- Serialize children that edit a shared tree. Read-only children may run in
  parallel.
- Use package-managed `worktree:true` for parallel editors and durable committed
  handoffs.
- Make shared-tree versus worktree behavior explicit in every editing workflow.

## Acceptance and integration

- The driver owns the accept/reject decision, not mechanical Git work.
- Review may be delegated to an independent child using the commit or patch.
- After acceptance, a designated integration child may apply/cherry-pick the
  delivery, rerun the gate, and report the resulting commit.
- The driver handles Git directly only for recovery or an integration failure.

## Completion and control

Use `subagent` for workflows and lifecycle actions. Async completion is
normally delivered automatically; do not call `subagent_wait` merely to wait or
poll. Block only when the current turn must return the child's result.

Use `subagent({ action: "status" | "steer" | "interrupt" | "stop", id })` for
one-shot control. Answer child questions with `subagent_supervisor` pending and
reply actions.

Own dropped batons. A result ending in “waiting on a background job” is a
handoff, not completion: verify the process or artifact and drive the next
step.

## Resume and recovery

Resume the actual child run ID, not an enclosing workflow ID. `children.list`
finds completed retained children; resume launches a new Pi process from the
persisted child session rather than continuing the old process.

Work that must survive a parent restart needs an explicitly async child and a
persisted parent session. Reopen that same parent session, then recover the
child with `status`, `steer`, `interrupt`, or `stop`. Missions help rediscover
workflow IDs but do not make an in-flight workflow script restartable.
