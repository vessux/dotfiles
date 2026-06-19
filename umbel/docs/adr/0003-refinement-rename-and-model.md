---
status: accepted
---

# Refinement: one discovery phase with sharpening as its engine; "triage" purged from the beads side

The discovery loop was described as three steps — capture → **triage** (keep/drop) → **prep**
(shape/promote) — with the sharpening skills (`grill-me`/`grill-with-docs`/`zoom-out`/`prototype`)
listed as tools "available throughout prep." That mis-modelled the work: sharpening is *how* the
keep/drop/promote decision gets made, not post-decision polish. And "triage" was badly overloaded —
it named the whole beads pass, the keep/drop step, bead adjectives (`untriaged`/`triaged-out`), the
pre-sort agent, **and** the unrelated matt-pocock `/triage` GitHub-label skill.

**Decision.** Merge triage + prep into a single phase, **refinement**, with the sharpening skills as
its engine. The spine becomes **capture → refine → outcome**. "Triage" is fully purged from the beads
side: the beads pass is a *refinement pass*, the pre-sort step is renamed `triage-presort` →
**`presort`**, and the `untriaged`/`triaged-out` bead adjectives are dropped. Afterward **"triage"
means exactly one thing** — the matt-pocock `/triage` skill, which sorts the GitHub issues *outsiders*
file (public tier only). Your own promoted issues land already `ready-for-agent` and skip it.

**Bead-state model — tier-differentiated** (raw captures must be distinguishable from refined,
delivery-ready work, and the two tiers hand off to delivery differently):

- **public** — refinement promotes a keeper to a GitHub Issue (labelled `ready-for-agent`) and then
  **closes the bead** (`bd close --reason "→ gh#N"`). beads only ever holds `open` (raw capture /
  in-refinement) and `closed` (resolved; close-reason = `→ gh#N` promoted vs `wontfix:` dropped).
  "Refined & ready for delivery" lives in GitHub, not in beads.
- **private** — beads *is* the backlog, so a refined keeper stays **open** and is marked
  **`stage:ready`** (`bd set-state <id> stage=ready` — beads' state-dimension convention, which adds a
  `stage:ready` label + an audit event). That marker is the in-beads line between raw capture and
  delivery-ready — the equivalent of what public expresses by closing+promoting. The delivery track
  consumes `bd ready` beads that are `stage:ready`; a claim moves it to `in_progress`, done closes it.

## Considered options

- **Keep triage and prep as separate phases** — rejected: it framed sharpening as optional polish and
  divorced the keep/drop decision from the work that actually informs it.
- **A dedicated refine-orchestrator skill** — rejected (YAGNI): the existing sharpening skills +
  `presort` cover it; a new skill would be one more thing to keep in sync.
- **Reuse public's exact `ready-for-agent` token as the private marker** — rejected in favour of the
  beads-native `stage:ready` state-dimension: it carries an audit event and is queryable. The
  cross-tier symmetry (both mean "refined, hand to delivery") is preserved in *meaning* without forcing
  one token across two different substrates (a GitHub label vs a beads state).

## Consequences

- The injected seeds, `bundles/discovery.md`, the `presort` agent, the `inject` envelopes, and ADR 0001's
  wording are updated; the `pocock/triage` skill and all `skills/pocock/**` files are untouched (they
  legitimately own the word).
- Delivery's private contract now consumes a bead that is `bd ready` *and* `stage:ready` (raw captures
  are not delivery units).
