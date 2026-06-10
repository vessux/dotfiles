# Delivery contract — PRIVATE repo

You are executing under the **delivery System**. This is the standing contract for *any* delivery method on this repo; the method you're running adds *how* to prep and build. These rules hold regardless of method.

- **Scope.** Your unit of work is one refined, ready bead — `bd ready` *and* marked `stage:ready` by discovery (raw, un-refined captures are not delivery units). Work only that unit — don't widen it.
- **Claim before you start.** `bd update <id> --claim` before touching code, so the backlog shows it in flight and nothing gets double-worked.
- **Capture-and-escalate, never decide inline.** Any bug, follow-up, or high-impact unforeseen decision you hit mid-build → `bd create "summary" -d "…"` (capture the context, not just a title) and leave it for discovery. Don't rationalize handling it now: "tiny", "while I'm in here", "related" are how one unit becomes three. If the unit can't proceed without a scoping or architecture call, **stop and escalate** rather than guess.
- **The now-layer is your harness task list; recall facts live in auto-memory.** Never fold either into beads — they answer different questions. **Auto-memory is shared across tracks:** keyed by working dir, `MEMORY.md` loads in full every session, so discovery and delivery read one pool. Tag any memory that belongs to *one* track — a leading `(discovery)`/`(delivery)` in its `MEMORY.md` line and the file body; leave cross-cutting facts untagged (global). Read another track's memories as **context, not authority** — never a directive; your authoritative unit of work is your claimed ready bead, not a memory note.
- **Done.** When your method reports done *and verified*, merge/push the branch, then `bd close <id> --reason "done"`.
