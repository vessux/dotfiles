# Umbel — Discovery & Delivery Workflow

The umbel subsystem defines this repo's two-track working method: **discovery** (turn raw input
into a ready backlog) and **delivery** (build and ship). This glossary fixes the language those
tracks share.

## Language

**Capture**:
A bead recorded the instant a thought, bug, or follow-up surfaces, holding the perishable context
— reasoning, evidence, competing options — the author has in hand at that moment.
_Avoid_: ticket, note, TODO

**Refinement**:
The single discovery phase that shapes a capture into delivery-ready work or drops it, with the
sharpening skills as its engine. Its output is twofold: the work to be done **and the proof that
the work is done as designed** (the Acceptance criteria) — a unit without stated proof is not
ready, however settled its decisions.
_Avoid_: triage, prep, grooming

**Acceptance criteria**:
The proof-of-done authored at Refinement, before any implementer context exists: named behaviours,
commands with expected observations, error-text contracts. Delivery answers them one-for-one and
may add evidence but never narrow them; an executable criterion must land as a test, not a
transcript. Because the exam is written by a disinterested earlier session, the implementing agent
cannot grade its own homework.
_Avoid_: definition of done, test plan, checklist

**Return**:
Delivery's verdict that a ready unit cannot be fulfilled as designed — the unit goes back to
discovery for revision, stripped of its ready state, carrying a mandatory reason recorded at the
moment the mismatch surfaced. Distinct from releasing a claim (the unit stays ready for another
worker); a Return says the *refinement* was wrong, not the worker.
_Avoid_: reject, bounce, unassign

**Pre-sort**:
The disinterested opening read of a Refinement pass: it inspects the unrefined inbox and proposes,
per Capture, whether to drop it, sharpen it (grill), or pass it through as ready — a recommendation
only, never a decision. Its worth is independence from the refiner, who is prone to wave work
through; so a "grill" proposal marks a Capture with an unresolved decision or unverified premise,
distinct from a "ready" one where only execution remains.
_Avoid_: triage, groom, sort

**Pregrill**:
The prep a Pre-sort pass files onto a grill-bound unit — its open decisions, its premises each
with a suggested verification, draft Acceptance criteria where the shape is visible — appended to
the unit as a dated note so the attended grill opens warm instead of cold-reading. Additive and
decision-free (the one write a Pre-sort may perform), re-filed only when missing or stale; the
grill's opening move is to re-verify its premises live, because code moves between passes.
_Avoid_: analysis, research notes, pre-work

**Adopt**:
To wire a repo up under a bundle's workflow — read the bundle body, inspect the repo's current
state, and provision everything the bundle needs to be fully utilised (tier marker, tooling,
per-repo skill defaults), adapting to what is already there.
_Avoid_: install, apply, enable, pin

**Clerk**:
The workflow's single command facade — the desk-laborer that executes mechanism (filing, syncing,
provisioning, reconciling) on the agent's behalf. The split is judgment vs paperwork: the agent
speaks a workflow verb and authors anything requiring judgment; the Clerk performs the menial,
deterministic steps exactly, so mechanism lives in scripts rather than in prose the agent must
re-read and obey each session. The Clerk is **opaque**: skills and agent-facing instructions speak
only Clerk verbs and never name the backing store — which tracker holds the inbox is the Clerk's
private business.
_Avoid_: dispatcher, wrapper, helper, tool, facade (as a name)

**Track**:
One of the two arms of the workflow — **discovery** (raw input → ready backlog) or **delivery**
(build and ship a ready unit). A session runs under exactly one track, declared by its injected
operating-rules.
_Avoid_: mode, stage, phase

**Bundle**:
An umbel artifact set — skills, hooks, agents, MCPs, plus a playbook — that equips a repo to run a
track. One track can be served by several bundles (delivery runs on **delivery-base** plus a
swappable method such as **delivery-superpowers**).
_Avoid_: plugin, pack, preset

**Claim**:
The atomic, identity-independent acquisition of one ready unit by a single worker before work
begins. Every Claim creates the canonical work-branch, which is the universal lock at the remote
(first push wins — ADR 0011); a bd-backed backlog adds a status transition as the online fast
path. Claiming without remote confirmation is a degraded, attended-only move — the collision is
caught at first push, never silently. Assignment alone is never a Claim.
_Avoid_: assign, take, grab, lock

**Impediment**:
A Capture whose subject is the *workflow itself* — friction between the agent and the harness,
tooling, or instructions that cost real effort to route around this session and **would recur,
burning tokens again, unless an instruction, skill, or tool is changed**. The criterion is
fixability, not the error flag: a tool result marked `is_error` from normal probing (an empty
`grep`, a guard that fails) is **not** an Impediment; a denied permission, an interface retried
three times before it worked, a misfiring bundled skill, or an ambiguous injected instruction
**is**. The highest-value class is friction with *our own* instructions and skills — those we
control and can fix, so they compound — as opposed to external-tool bugs we can only work around.
_Avoid_: roadblock, friction, snag, bug, error

**Glean**:
The retrospective gathering of *compounding signals* from a finished session — friction,
techniques, decisions worth recording — that the agent never captured in the moment because it
was heads-down on the task. A disinterested fork re-reads the session transcript (the full record,
which survives compaction), recognises each signal, and files it as a typed Capture. Its discipline
is **compound engineering**: each session leaves leverage that cheapens the next. The gleaned
categories: the **Impediment** (`type:impediment`), the **criteria-miss** (the Acceptance criteria
were weak or incomplete), the **sort-miss** (a Pre-sort proposal the human overrode, an empty
grill, or a returned wave-through), and the **prep-miss** (a Pregrill premise never true, an
agenda gap, or draft criteria rewritten wholesale). The list is open by design — the standing law
is that **every judgment point in the workflow declares its loop**: the signals that indict it,
the category that carries them, and the guidance artifact its lessons land in.
_Avoid_: retro, sweep, scan, audit

**Compound**:
The cross-session *reduce* over the **Impediment** corpus. It reads every `type:impediment`
**Capture**, clusters the recurring friction into a ranked taxonomy, and proposes — per class — the
instruction, skill, or tool change that would retire it: a decision-free agenda the human takes
into a grill. Where **Glean** *maps* (harvesting one session's friction into Captures), Compound
*reduces* (turning the accumulated Captures into a fix agenda across sessions); both are the
**compound engineering** discipline. It ranks by recurrence and flags recency — a class still
recurring vs. one gone quiet — but claims no fix-linkage. Like **Pre-sort** it is a read-only,
ephemeral fork: it proposes, never mutates the corpus, and writes no committed record. Distinct
from the dormant `plannotator/compound` *tool*, which reduces the human's *plan-rejection* feedback
to improve planning, not agent friction.
_Avoid_: friction, digest, taxonomy, audit

## Relationships

- **Refinement** shapes a **Capture** into a delivery-ready bead, or drops it.
- **Pre-sort** opens a **Refinement** pass with an independent proposal per **Capture** — drop,
  grill, or ready — that the human acts on; it proposes, never decides or mutates.
- To **Adopt** a bundle is to provision a repo so its skills are fully utilised — distinct from
  *pinning* (a product-level launch route) and from merely loading the bundle's skills.
- A **Bundle** equips a repo to run a **Track**; one **Track** may be served by several **Bundles**
  (a base contract plus a swappable method).
- A **delivery** **Track** session opens by **Claim**ing one ready unit; the Claim is atomic, so
  concurrent workers — even sharing one identity — never take the same unit.
- The **Clerk** executes the mechanism of every workflow verb (**Capture** filing, **Claim**,
  finish); the agent keeps the judgment half — deciding *which* verb, and authoring whatever the
  verb needs written.
- An **Impediment** is a **Capture** whose subject is the workflow, not the task. It is recorded
  as a bead like any other Capture, but earns its keep only when a change to an instruction,
  skill, or tool would stop it recurring; the same friction hit across many sessions (e.g. a
  worktree teardown that fails on every delivery finish) is the signal it is worth fixing.
- **Glean** produces typed **Capture**s retrospectively from a session transcript; its first
  category is the **Impediment**. It is the compound-engineering counterpart to ambient capture:
  ambient capture records a signal as it surfaces, Glean recovers the ones that slipped past while
  the agent was heads-down. Both tracks run it (one source skill, dual-listed); it is itself a
  fork, like **Pre-sort**, but unlike Pre-sort it *writes* — because capture is ungated by design.
- **Compound** is the cross-session **reduce** counterpart to **Glean**'s per-session harvest:
  Glean files the **Impediment** **Capture**s, Compound ranks the recurring ones into a fix agenda.
  Like **Pre-sort** it is a read-only, ephemeral fork that proposes and never mutates; unlike
  **Glean** it writes nothing at all.

## Example dialogue

> **Dev:** "Should a **Capture** just be a one-line pointer I flesh out later?"
> **Domain expert:** "No — a **Capture** is a snapshot of the context you have *right now*. That
> context won't survive to **Refinement**, so record it at capture time; **Refinement** sharpens
> what's there, it doesn't reconstruct it."

## Flagged ambiguities

- "Capture" was read two ways — a terse pointer (re-find the thought later) vs a perishable-context
  snapshot. Resolved: it's a **perishable-context snapshot**; the body is recorded at capture time
  because the context won't survive to refinement.
- "Adopt" was collapsed into "pin the bundle" / "load its skills" — resolved: adoption is the
  per-repo **setup procedure** derived from the bundle body (tier, tooling, skill defaults); pinning
  only routes launches and skill-loading is automatic, so neither alone is adoption.
- Memory scoping was first framed as "bundle-specific" — resolved: auto-memory belonging to one arm
  of the workflow is **track-scoped**, not bundle-scoped (a fact about delivery work must survive
  swapping the delivery method); memory with no track tag is **global**. (Mechanism: ADR 0008.)
- "Claim" was conflated with GitHub **assignment** ("assign the issue to yourself") on the public
  tier — resolved: a **Claim** is *atomic and identity-independent*; assignment is neither (same-user
  agents share `@me`), so it cannot serve as the claim. Public claims via canonical-branch
  ref-creation instead (ADR 0011).
- "Tier" (public/private) conflated two independent axes — resolved: **backlog location** (where
  the ready pool lives) and **merge gate** (the autonomy dial, review-required vs auto-merge). The
  repo whose marker said `private` while its remote was public proved visibility was never the real
  variable. The tier wording is retired; the frozen bundle generation still speaks it.
