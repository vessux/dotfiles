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

## Relationships

- **Refinement** shapes a **Capture** into a delivery-ready bead, or drops it.

## Example dialogue

> **Dev:** "Should a **Capture** just be a one-line pointer I flesh out later?"
> **Domain expert:** "No — a **Capture** is a snapshot of the context you have *right now*. That
> context won't survive to **Refinement**, so record it at capture time; **Refinement** sharpens
> what's there, it doesn't reconstruct it."

## Flagged ambiguities

- "Capture" was read two ways — a terse pointer (re-find the thought later) vs a perishable-context
  snapshot. Resolved: it's a **perishable-context snapshot**; the body is recorded at capture time
  because the context won't survive to refinement.
