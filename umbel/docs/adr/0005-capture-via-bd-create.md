---
status: accepted
---

# Capture via `bd create`, not `bd q`: a capture carries a body

ADR-0001 named `bd q` the always-open capture inbox verb. But a capture is a *perishable-context
snapshot* (see `umbel/CONTEXT.md`) — it holds the reasoning, evidence, and options the author has
in hand at the moment, because that context won't survive to refinement. `bd q` is title-only, so
that content had nowhere to go but the title, which jammed against beads' 500-char title cap
(observed on every open bead in dotfiles: 404–496-char titles, empty bodies).

**Decision.** The capture verb is **`bd create`** on both tiers: a one-line summary as the title,
the dump in `-d` / `--stdin` (the body has no length limit), `--silent` for just the ID. `bd q` is
dropped from the discovery and delivery seeds, the `presort` guard, and `docs/agents/issue-tracker.md`.
This supersedes ADR-0001's `bd q` capture-verb decision and the `bd q` mentions in ADRs 0003/0004.

## Considered options

- **Keep `bd q`, use `bd create` only when a capture has a body** (escape-hatch) — rejected: it
  leaves a body-less default on the ambient hot path and relies on the agent *noticing* it has a
  body and deviating. The observed failure is precisely that agents don't deviate — they reach for
  the default and overstuff the title. Removing the body-less default is the point.
- **A hard guard (wrapper / git hook rejecting long titles)** — rejected (YAGNI): the failure was
  structural (no body outlet), not agents ignoring guidance. Once `bd create -d` gives the dump a
  home, a one-line convention + a worked example suffices; the ~80-char title is a target, not an
  enforced limit.
- **Stay on `bd q` and just instruct shorter titles** — rejected: a title-only tool cannot hold a
  capture's body no matter how the instruction is worded; the content has nowhere to go.

## Consequences

- Both discovery seeds, both delivery seeds, the `presort` guard list, `docs/agents/issue-tracker.md`,
  and ADR-0001 wording are updated. The bundle ships `bd create` as the capture verb to every
  discovery/delivery repo.
- Existing maxed-title captures (the dotfiles inbox) need a one-time migration: split title → body.
  Tracked as a separate capture.
