---
name: clerk-discovery
description: >-
  Discovery track using Clerk verbs: capture raw input, pre-sort the inbox, refine keepers, and hand ready units to delivery.
skills:
  - pocock/grill-me
  - pocock/grill-with-docs
  - pocock/zoom-out
  - pocock/prototype
  - pocock/handoff
  - plannotator/annotate
  - plannotator/last
  - local/clerk-presort
hooks:
  - local/clerk-session-start
mcps:
  - local/tuidriver
---

# clerk-discovery

Discovery shapes raw input into ready units. Speak through **Clerk**: use `clerk capture` for new
thoughts, `clerk inbox ...` for the inbox, and `clerk inbox ready` only after refinement has named
the work and the proof.

## Applying

Use `clerk doctor` first. If it reports missing setup, follow its prescription. Do not encode Clerk
mechanism in project instructions; keep the shared face focused on how to ask for work and how to
review results.

## Refinement loop

1. Capture raw input with `clerk capture "summary"` and a body when context matters.
2. Open a pass with `/presort`. It proposes drop / grill / ready / needs-input and may add
   decision-free pregrill notes through `clerk inbox pregrill`.
3. Refine with the grill and architecture skills until each keeper has explicit acceptance
   criteria.
4. Mark keepers ready with `clerk inbox ready`; drop the rest through Clerk.

`clerk glean` may also file missed workflow signals; those return to the same inbox and are refined
like any other capture.
