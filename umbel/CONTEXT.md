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
sharpening skills as its engine.
_Avoid_: triage, prep, grooming

**Pre-sort**:
The disinterested opening read of a Refinement pass: it inspects the unrefined inbox and proposes,
per Capture, whether to drop it, sharpen it (grill), or pass it through as ready — a recommendation
only, never a decision. Its worth is independence from the refiner, who is prone to wave work
through; so a "grill" proposal marks a Capture with an unresolved decision or unverified premise,
distinct from a "ready" one where only execution remains.
_Avoid_: triage, groom, sort

**Adopt**:
To wire a repo up under a bundle's workflow — read the bundle body, inspect the repo's current
state, and provision everything the bundle needs to be fully utilised (tier marker, tooling,
per-repo skill defaults), adapting to what is already there.
_Avoid_: install, apply, enable, pin

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

## Relationships

- **Refinement** shapes a **Capture** into a delivery-ready bead, or drops it.
- **Pre-sort** opens a **Refinement** pass with an independent proposal per **Capture** — drop,
  grill, or ready — that the human acts on; it proposes, never decides or mutates.
- To **Adopt** a bundle is to provision a repo so its skills are fully utilised — distinct from
  *pinning* (a product-level launch route) and from merely loading the bundle's skills.
- A **Bundle** equips a repo to run a **Track**; one **Track** may be served by several **Bundles**
  (a base contract plus a swappable method).

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
