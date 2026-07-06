---
status: accepted
---

# Delivery-gate: server-side proof classes, acceptance criteria in the definition of ready, and the judgment-loop law

Merge is the gating point of delivery, but on a no-CI repo "green" is vacuous, and client-side
discipline is the compliance-decay class dotfiles-b6r documents (the agent that skips the method
also skips a local gate). We gate merges with a **server-side required check — the
delivery-gate** — that validates proof the *workflow itself* can mandate, method-agnostically
(per ADR 0002 this is a base-contract obligation; no method required). The deepest class fixes
the fully-agentic grading problem: **the implementer must not write its own exam**, so acceptance
criteria are authored at Refinement, before any implementer context exists, and folded into the
definition of `stage:ready`.

## Decision

Four proof classes, with a strict authority split:

- **C1 — protocol proof** (server-checkable): branch matches `delivery/<id>`; the PR links exactly
  one unit and it matches the branch's id; branch current with main. The workflow auditing its own
  invariants — claim-before-work, one unit per PR, traceability.
- **C2 — verification proof** (structure mandatable, truth not): a schema'd verification block in
  the PR body, failing on absence. Truth comes from C3 where a test surface exists; the gap is
  deliberate pressure — a repo's gate gains teeth exactly as fast as its tests do.
- **C3 — executable proof**: run the repo's checks. This repo's first real test surface is the
  epic's own deliverable (clerk's bats suite — printed output tested like exit codes — plus
  shellcheck on `bin/`), so the no-CI floor is genuine CI, not a placeholder.
- **C4 — acceptance proof**: Refinement's output is twofold — the work *and the proof it is done
  as designed*. `clerk inbox ready` refuses units without acceptance criteria (presence is
  structural; quality is grill judgment); `submit` stamps the unit's criteria into the PR body and
  requires one evidence entry per criterion — delivery may add evidence, never narrow; **an
  executable criterion must land as a test, not a transcript** (workflow-level TDD). If delivery
  cannot fulfil the criteria as designed, `backlog return` sends the unit back to discovery with a
  mandatory reason, auto-filed as a capture.

Authority split: the server-side check is authoritative for what the server can see (C1–C3, and
C4's criterion-evidence correspondence, which submit made server-visible); claim-state truth stays
clerk-side (`submit`/`finish` hold `bd` access; an Action cannot read the Dolt store). `clerk
submit` runs the same gate script as a local preflight — fast feedback, never the authority.

**Review-required branch protection is the attended dial** (the merge key, K1 of ADR 0015):
today's posture is review-required + delivery-gate; flipping a repo toward unattended is removing
review-required and leaving the check — a platform setting, not prompt discipline.

**The judgment-loop law**: every judgment point in the workflow declares its compounding loop —
the signals that indict it, the glean category that carries them, and the guidance artifact its
lessons land in. One circuit for all loops: signals are filed ungated (clerk-filed ambient
captures; glean's transcript sweep) → they land in the ordinary inbox → pre-sort clusters them via
`inbox dups` → one grill lands the cluster as a single compounded unit → the deliverable is a
**gated edit to the guidance artifact**. The intent anchor is the human at the attended grill; the
loops compound the *craft* so human attention is spent on rulings, not proof-mechanics.

Loop map at inception:

| Judgment point | Category | Guidance artifact |
|---|---|---|
| Grill criteria authoring | `criteria-miss` (returns; trivially-green criteria; evidence-beyond-criteria) | acceptance playbook (`umbel/docs/acceptance-playbook.md`, lazily created, loaded by grill skills) |
| Pre-sort classification | `sort-miss` (proposal-vs-disposition divergence read from transcripts; empty grills; returned wave-throughs) | presort successor's judgment guidance |
| Pregrill prep | `prep-miss` (never-true premises; agenda gaps; draft criteria rewritten wholesale) | pregrill guidance in the same skill |
| Workflow friction | `impediment` (ADR 0012) | the instruction/skill/tool at fault |

Delivery *build* craft is deliberately uncovered — that is the swappable method's concern;
methods declare their own loops under the law.

**Pregrill** (the prep half of the loop): pre-sort's successor is decision-free with exactly one
write verb — `clerk inbox pregrill <id>` appends a dated, structured, state-neutral note (open
decisions, premises each with a suggested verification, draft criteria) **onto the unit itself**
(a bead exists to hold perishable context). Dispositions stay ephemeral per pass; prep persists.
Pregrill fires per-delta (note missing or stale — body edited after note date, cluster grew),
never per-pass, and never at capture time (prep before classification spends on the doomed).
Pre-sort remains **manually invoked**, like today; the ambient chain (SessionStart: glean →
presort-delta) is designed but shelved as a later dial. The grill's opening move is to re-verify
the pregrill's premises live.

## Considered options

- **Review-only gate** — rejected as the floor: blocks unattended forever; survives as the
  attended dial.
- **Submit-side gate only** — rejected as authority: client-side discipline is b6r's decay class;
  survives as the preflight.
- **Method-compliance check (superpowers artifacts)** — rejected as the base gate: the workflow
  can only honestly mandate proof of its *own* invariants; per-method checks stack on top as
  additional required checks.
- **Pregrill at capture time** — rejected: preps captures that refinement will drop, and smuggles
  the classifier into the prep fork; glean's batch filings would fan out forks blindly.
- **Persisting pre-sort proposals as state** to audit overrides — rejected: proposals stay
  ephemeral by ruling; the session transcript is the audit record and glean is its reader.

## Consequences

- This repo gains CI (the delivery-gate workflow) and branch protection as part of the epic —
  no repo in the workflow stays gate-less.
- `stage:ready` is redefined: no open decision **and** stated acceptance criteria. Pre-sort may
  not propose `ready` for a criteria-less capture (demotes to grill, may draft criteria as a
  proposal).
- The squash commit carries the criteria-evidence summary, so `git log` is the audit surface the
  `criteria-miss` glean reads.
- Glean's category list grows to four; `/glean`'s harvest mechanism is unchanged (ADR 0012,
  mechanics now `clerk glean` per ADR 0015).
