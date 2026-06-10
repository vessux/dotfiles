---
status: accepted
---

# Pre-sort is a `context: fork` skill, not a standalone agent; `needs-grill` stays ephemeral

A refinement pass surfaced a failure mode: the refining agent marked design-fork captures
`stage:ready` **by fiat** — picking an approach and readying them — instead of sharpening them
first. (Concretely, two captures whose bodies *named* competing options were waved through as
"shaped enough".) The refining agent has a standing bias toward calling work done, and nothing in
the loop surfaced "this capture carries an unresolved decision" independently of that agent's own
judgment. ADR-0003 already posits an independent **pre-sort** step (the `presort` agent) that
proposes type/priority/keep-drop without mutating — but as an *agent* it has no canonical
user-facing entry and isn't reliably reachable, and it didn't carry a grill-vs-ready signal.

Two questions had to be answered: what **substrate** pre-sort should have (agent vs skill), and
whether the "needs grilling" signal should **persist** as bead state.

**Decision.** Pre-sort is a **`/presort` skill** declared `context: fork` — a documented Claude
Code feature where the skill body runs as a fresh subagent's prompt (`agent: general-purpose`,
tools restricted to read-only: Bash/Read/Grep/Glob). One artifact is therefore **both** the
canonical slash-command entry to a refinement pass **and** the isolated, independent classifier.
It runs over the *unrefined* inbox only (`open`, not `stage:ready`), read-only, and emits a
**proposal table** classifying each capture as one of **drop / grill / ready / needs-input**. The
human (or main agent) acts on the table; pre-sort never mutates.

**The grill/ready line.** `ready` = the decision is already made (or there is none) and only
execution remains. `grill` = more than one defensible answer exists, or correctness hinges on an
unverified premise (also: architectural blast radius). This is the line the refining agent
mis-drew in the motivating failure.

**`needs-grill` is ephemeral** — a column in the proposal table, re-derived each pass, **not** a
bead state. There is no enforcement gate. So ADR-0003's bead-state model (raw capture /
`stage:ready` / closed) is **unchanged** — this ADR is purely additive (one skill).

## Considered options

- **Keep pre-sort a standalone subagent (status quo)** — rejected: a subagent cannot be invoked as
  a slash command, so there is no canonical `/presort` entry, and auto-delegation by description is
  unreliable; it also left the dispatch gap tracked as dotfiles-2ab.
- **A `/presort` skill that classifies inline in the main agent's context** — rejected: it loses
  the independence that is pre-sort's entire purpose (a documented anti-pattern). The refiner's
  wave-it-through bias re-contaminates the classification — the very failure we are fixing.
- **A skill that *uses* a separate pre-sort agent (two artifacts)** — rejected: "one more thing to
  keep in sync" (the cost ADR-0003 named when it declined a refine skill). `context: fork`
  collapses skill + subagent into a single artifact, so that objection does not apply.
- **A persistent `stage:needs-grill` bead state** — rejected: with no enforcement gate it has no
  teeth; its token "saving" over re-derivation is largely illusory because captures rot (a stale
  classification would mislead — one capture was resolved out-of-band during the very pass that
  motivated this), so a persisted mark would need re-validation anyway; and it forces a bead-state
  model change. Ephemeral re-derivation doubles as re-validation against current reality, and
  `/presort` is human-invoked per pass (not an auto-loop), so the cost is paid deliberately.
  *Revisit only* for large, slow-draining inboxes — then persist with a `classified-at <commit>`
  staleness stamp.
- **Hard enforcement (a beads hook rejecting `stage:ready` while `needs-grill`)** — rejected:
  convention suffices once the rule is a bright line keyed off an *independent* proposal rather than
  the refiner's self-judgment; consistent with ADR-0005's convention-over-machinery stance.

## Consequences

- Retire `umbel/agents/local/presort/AGENT.md`; remove `agents: [local/presort]` from
  `umbel/bundles/discovery.md`; add the `presort` skill to the bundle's skills list.
- Both discovery seeds' Pre-sort step is rewritten: **status → `/presort` → human decides**
  (auto-promote the `ready` ones, grill the `grill` ones, or grill even a `ready` one), describing
  the proposal table, the grill/ready line, and that `needs-grill` is ephemeral.
- **Supersedes dotfiles-2ab** (presort not dispatchable): `context: fork` is that bead's own
  "option B"; the custom-agent-registry fix (option A) is unnecessary.
- **Amends ADR-0003**: pre-sort's *substrate* changes from an agent to a `context: fork` skill. The
  triage→refinement rename, the "triage" purge, and the bead-state model from ADR-0003 all stand.
- `umbel/CONTEXT.md` gains the **Pre-sort** term.
- Tracked as dotfiles-ayb (`stage:ready`).
