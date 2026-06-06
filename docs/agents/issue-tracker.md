# Issue tracker: beads

Issues for this repo live in **beads** (the `bd` CLI), **not** GitHub. This repo runs the
discovery track (private tier): beads *is* the backlog. Do **not** create GitHub issues here,
even though the `origin` remote is GitHub.

## Lifecycle

The whole lifecycle lives in beads:

- **Raw capture** — an **open** bead with no `stage:*` label. Created ambiently with `bd q "…"`.
- **Ready for delivery** — an open bead marked `stage:ready` (`bd set-state <id> stage=ready`).
  This is the line between a raw capture and work the delivery track can pull.
- **Resolved** — a **closed** bead. The close-reason says whether it was delivered or dropped
  (`bd close <id> --reason "wontfix: …"`).

`bd ready` + dependencies + epics drive the work directly. The delivery track pulls beads that are
both unblocked (surfaced by `bd ready`) and marked `stage:ready`.

## When a skill says "publish to the issue tracker" / "create an issue"

Capture into beads:

- Quick capture: `bd q "<title>"` (returns the ID).
- Fuller issue: `bd create` (set type/priority, body, etc.).

Do **not** run `gh issue create`.

## When a skill says "fetch the relevant ticket"

`bd show <id>`. The user normally passes the bead ID directly.

## When a skill says "break this into issues" (e.g. /to-issues)

Create one bead per vertical slice, wire dependencies with `bd dep`, group into an epic where
useful, and mark each ready slice `stage:ready`. There is no PRD-to-self and no separate promotion
step — the bead *is* the work item.

## Triage state

See `docs/agents/triage-labels.md` for how the canonical triage roles map onto beads states and
close-reasons.
