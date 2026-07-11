---
name: clerk-delivery-base
description: >-
  Delivery base contract using Clerk verbs: claim one ready unit, build only that unit, submit proof, finish through the reconciler.
skills:
  - plannotator/annotate
  - plannotator/last
  - pocock/grill-with-docs
hooks:
  - local/clerk-session-start
mcps:
  - local/tuidriver
---

# clerk-delivery-base

The invariant delivery contract is small because Clerk owns the paperwork. A delivery session works
one ready unit from claim to finish and leaves every judgment artifact visible in the pull request
and the unit record.

## Session loop

1. `clerk backlog next` to choose one ready unit.
2. `clerk backlog claim <id>` before editing; enter the path printed as the last line.
3. Build only that unit. Capture unrelated discoveries with `clerk capture`.
4. `clerk backlog submit <id>` when the change and evidence are ready.
5. `clerk backlog finish` until the reconciler says the unit is merged, waiting, or needs another
   build loop.
6. If the unit cannot be fulfilled as refined, use `clerk backlog return <id>` with the reason.

## Keys

- Merge key: the platform gate decides when a submitted change may merge.
- Initiation key: a human or scheduler starts sessions.
- In-session key: the harness decides which Clerk verbs may run without a prompt.

Use `clerk doctor` when the setup or next verb is unclear. Do not replace Clerk verbs with
mechanism copied from memory.
