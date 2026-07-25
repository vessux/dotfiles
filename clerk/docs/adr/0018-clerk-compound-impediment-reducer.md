---
status: accepted
---

# `clerk compound` — a read-only longitudinal reduce over the Impediment corpus (Gap B)

Glean (ADR 0012) files per-session `type:impediment` beads — Gap A. Cross-session
recurring-friction detection was scoped out as **Gap B** (dotfiles-8vq), to be modelled on
`plannotator/compound`'s longitudinal map-reduce. The corpus now exists (50+ Impediment beads).
This ADR fixes what Gap B is and, deliberately, what it is not.

## Context

Three facts constrain the design:

1. **The corpus is a bd custom type, and it is prose.** The live producer (`clerk glean`, dft.6,
   fired by the SessionStart hook) files `bd create --type impediment`; the ADR-0012 `/glean`
   skill would file a `type:impediment` *label*, but it is not installed. Either way the bead
   carries only a title + free-text body — the structured signals `extract.py` computes
   (`error_class`, `retry_count`, tool, cost) are not persisted onto it.
2. **The loop map already routes impediments to fixes.** ADR 0016: glean → inbox → Pre-sort
   clusters (via dups) → grill lands the cluster as one compounded unit → gated edit. Pre-sort
   already dedups the *open inbox* source-agnostically (dotfiles-o1o). So a Gap-B step that
   *files* compounded units would collide with Pre-sort and risk inbox flood.
3. **Remediation is a grill decision** (ADR 0012): glean deliberately leaves the fix open, because
   choosing which instruction to change has more than one defensible answer.

## Decision

**`clerk compound`** — a clerk verb, the *reduce* sibling to `clerk glean`'s *harvest*, read-only
and ephemeral.

- **A clerk verb, not a skill.** Its whole input is the bd Impediment corpus; a skill querying bd
  would break the opacity ruling (ADR 0015). Glean hit the same fork and became a verb. Bash owns
  the deterministic parts (query `--type impediment`, tolerate the label variant, group, count
  recurrence, read status + dates); a reduce fork owns the judgment (name the friction classes from
  the prose bodies, recommend one instruction/skill/tool change per class), returning a JSON
  clustering that the deterministic half then counts, ranks, and renders. The fork is invoked
  through a stubbable env seam (`CLERK_COMPOUND_REDUCE_CMD`, defaulting to `claude -p`) mirroring
  glean's `CLERK_GLEAN_JUDGMENT_CMD`, so the acceptance tests pin the deterministic assembly against
  a canned clustering rather than the non-deterministic model. One fork for the current corpus;
  map-reduce batching only if it grows (the ADR 0010 instinct).
- **Read-only — the defining invariant.** It files no Capture, closes none, relabels none. It is
  **Pre-sort's longitudinal cousin** (a read-only, ephemeral proposal), not Glean's write-fork. The
  Impediment beads are already the persistent record; Compound only analyzes them.
- **Consumes beads, not transcripts.** No transcript re-scan — that would ignore the human triage
  the beads carry, re-do glean's per-session work, and stand up a third transcript parser (ADR 0010
  gates sharing even the two existing ones). It reduces over the prose bodies, exactly as
  `plannotator/compound` reduces over prose denial reasons.
- **Ranks by recurrence; flags recency, not fix-linkage.** Recurrence count is the primary rank key
  (token-cost is inconsistent prose — a qualitative secondary at most). "Did the fix stick?" is a
  recurrence-*recency* heuristic (recent occurrences = live; quiet-since-a-date = possibly
  resolved), **not** a claim that a fix shipped: beads do not link to the delivery unit that fixed
  them.
- **Ephemeral output.** A terse ranked agenda to stdout (16-color ANSI, capability-gated); anything
  richer to an uncommitted state path (`~/.local/state/clerk/`), never a committed worklog (the
  no-worklog rule; clear of the dotfiles-l1d committed-KB tension). The human reads the agenda and
  grills the top class; the fix is a normal gated delivery unit.

The loop closes without a meta-bead layer: grill a class → deliver the gated fix → the now-closed
Impediments plus the ADR/instruction change are the durable trace → the next `clerk compound` run
sees the recency shift.

**Naming.** `clerk compound` names the *compound-engineering* discipline this verb performs. It is
distinct from the dormant, vendored `plannotator/compound` *skill*, which reduces the human's
plan-rejection feedback to improve planning (not agent friction). Convention: the tool is always
written `plannotator/compound`, the verb always `clerk compound`. (`clerk reduce` was the runner-up
— it names the member's role rather than the family — and is kept as a rename option.)

## Considered options

- **Re-scan transcripts for structured signal** — rejected: discards the human triage in the beads,
  re-does glean's work, and duplicates the ADR-0010-gated parser.
- **Auto-file a compounded grill unit per class** (Glean's write-fork) — rejected: overlaps
  Pre-sort's clustering, risks inbox flood, and makes a "worth fixing" call that is a grill decision.
- **A skill, modelled on `plannotator/compound`** — rejected: it would name bd, breaking the opacity
  ruling.
- **True fix-linkage in v1** — deferred: needs a persisted fix-link/close-reason (a
  glean-enrichment change + back-fill of existing prose beads). Earned when the recency heuristic
  proves insufficient, not before.

## Consequences

- New clerk verb `clerk compound`; deterministic bash + one `claude -p` reduce fork.
- v1 reports recurrence + a recency signal. True fix-linkage and glean structured-field enrichment
  are a deferred follow-up capture.
- `umbel/CONTEXT.md` gains the **Compound** term (disambiguated from `plannotator/compound`).
- Acceptance criteria pin the read-only invariant, corpus selection, and the empty-corpus exit path
  as tests (the dotfiles-dft contract-divergence lesson: contracts two implementations could
  reasonably decide oppositely must be written down, not left to delivery).
- Tracked as dotfiles-8vq (stage:ready).
