---
status: accepted
---

# Delivery as an invariant base + swappable execution methods

`discovery` defines scope (creative); `delivery` executes it (mechanical). To experiment
with more than one execution methodology without rebuilding the surrounding lifecycle each
time, `delivery` is split into a stable contract and swappable methods.

**`delivery-base`** is the invariant System: it owns the scope lifecycle — consume one
ready unit (by tier: a GitHub issue / a `bd ready` bead), claim it, **capture-and-escalate
(never decide a high-impact scope or architecture call inline)**, mark it done (+ a review
gate on public) — plus the tooling common to every method (`plannotator/annotate`+`last`,
`pocock/grill-with-docs`, the `tuidriver` MCP). A **`delivery-<method>`** bundle (first:
`delivery-superpowers` = `extends: [delivery-base, superpowers]`) owns everything between
claim and done: branching strategy, prep, execution, the review *flow*, and whether/how it
records decisions. New methods swap in by extending `delivery-base` and adding only their
own procedure.

The operating rules are **injected per session**, not written into the repo: a SessionStart
hook reads a committed repo-root `.repo-visibility` marker (`public`|`private`) and injects
the tier-matched ruleset as `additionalContext`. `delivery-base` always injects the
contract; a method injects its own procedure block only if its skills don't already carry
it (superpowers' own announce-hook + skill web does, so `delivery-superpowers` adds none).
This builds entirely from bundle artifacts — **umbel itself is unchanged** (see umbel
`docs/worklog.jsonl` @ 2026-06-01T09:29:20Z).

## Considered options

- **Seed the ruleset into a gitignored `CLAUDE.local.md`** (the original plan) — rejected:
  needs file-write + idempotency + `.gitignore` machinery, drifts per-repo, must be
  re-seeded on every change, and writes into the project tree. The ruleset is only needed
  while a bundle is loaded; raw beads capture works regardless (beads is a global CLI).
  Superseded by injection.
- **Inject via `--append-system-prompt`** — rejected: one-shot launch flag with undocumented
  behavior across compaction. A SessionStart hook re-fires on `compact`, mirroring how
  project-root `CLAUDE.md` is re-read, and uses the same conversation-context channel.
- **One monolithic `delivery` bundle** (`extends: [superpowers, plannotator]`) — rejected:
  fuses the invariant lifecycle with one execution discipline, so methods can't be swapped,
  and it pulled unused plannotator skills wholesale.
- **`common` + per-tier delta seeds, concatenated** — rejected: a kit of fragments reads as
  optional and the agent drifts; each injected block must be a complete, coherent procedure
  (so: one self-contained seed per tier).
- **Cherry-pick superpowers skills** — rejected: superpowers is a cohesive system (meta-skill
  + announce-hook + interlinked skills, built to be extended), so it's extended whole; loose
  collections (plannotator) are cherry-picked to only what's used.
- **A-injection: one woven seed per method, hookless base** — rejected in favor of B (base
  injects the contract; a method adds a procedure block only if needed). Base owns all
  tier-awareness, methods stay tier-agnostic, and a new method authors only its procedure.
- **Put decision-record location/policy in base** — rejected: every method records
  differently, so it's method-owned; base says nothing about it.
- **Share `delivery-base` with `discovery`** — deferred: base is delivery-only for now;
  discovery stays a single monolithic bundle and may get its own base later.

## Consequences

- Adding a delivery method = a thin bundle (`extends: [delivery-base, <skills>]`) + its own
  procedure hook *only if* its skills don't self-carry. Contract, tier-awareness, and shared
  tooling come for free.
- A delivery session injects **two coherent blocks** at start (base contract + method),
  re-asserted on `startup`/`clear`/`compact`.
- The only thing written into a repo is a committed one-line `.repo-visibility` marker
  (shared with discovery; resolves offline in clones/sandboxes); committed `CLAUDE.md` stays
  the public face.
- `discovery` and `delivery` are independently swappable tracks over a shared tier marker.
- Bundle frontmatter `description:` must avoid `": "` (colon-space) — a YAML plain-scalar
  break silently drops the bundle from the index (filed as a umbel papercut).
