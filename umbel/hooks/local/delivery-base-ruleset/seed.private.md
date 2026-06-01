# Delivery contract — PRIVATE repo

You are executing under the **delivery System**. This is the standing contract for *any* delivery method on this repo; the method you're running adds *how* to prep and build. These rules hold regardless of method.

- **Scope.** Your unit of work is one `bd ready` bead. Work only that unit — don't widen it.
- **Claim before you start.** `bd update <id> --claim` before touching code, so the backlog shows it in flight and nothing gets double-worked.
- **Capture-and-escalate, never decide inline.** Any bug, follow-up, or high-impact unforeseen decision you hit mid-build → `bd q "…"` and leave it for discovery. Don't rationalize handling it now: "tiny", "while I'm in here", "related" are how one unit becomes three. If the unit can't proceed without a scoping or architecture call, **stop and escalate** rather than guess.
- **Done.** When your method reports done *and verified*, merge/push the branch, then `bd close <id> --reason "done"`.
