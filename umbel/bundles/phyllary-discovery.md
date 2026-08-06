---
name: phyllary-discovery
description: >-
  Discovery track using Phyllary verbs: capture raw input, pre-sort the inbox, refine keepers, and hand ready units to delivery.
skills:
  - pocock/grill-me
  - pocock/grill-with-docs
  - pocock/zoom-out
  - pocock/prototype
  - pocock/handoff
  - plannotator/annotate
  - plannotator/last
  - local/phyllary-presort
hooks:
  - local/phyllary-session-start
mcps:
  - local/tuidriver
---

# phyllary-discovery

Discovery shapes raw input into ready units. Speak through **Phyllary**: use `phyllary capture` for new
thoughts, `phyllary inbox ...` for the inbox, and `phyllary inbox ready` only after refinement has named
the work and the proof.

## Applying

Use `phyllary doctor` first. If it reports missing setup, follow its prescription. Do not encode Phyllary
mechanism in project instructions; keep the shared face focused on how to ask for work and how to
review results.

## Refinement loop

1. Capture raw input with `phyllary capture "summary"` and a body when context matters.
2. Open a pass with `/presort`. It proposes drop / grill / ready / needs-input and may add
   decision-free pregrill notes through `phyllary inbox pregrill`.
3. Refine with the grill and architecture skills until each keeper has explicit acceptance
   criteria.
4. Mark keepers ready with `phyllary inbox ready`; drop the rest through Phyllary.

`phyllary glean` may also file missed workflow signals; those return to the same inbox and are refined
like any other capture.
