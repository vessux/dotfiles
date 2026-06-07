# Issue tracker: beads

Issues for this repo live in **beads** (the `bd` CLI), **not** GitHub. This repo runs the
discovery track (private tier): beads *is* the backlog. Do **not** create GitHub issues here,
even though the `origin` remote is GitHub.

## Lifecycle

The whole lifecycle lives in beads:

- **Raw capture** — an **open** bead with no `stage:*` label. Created ambiently with `bd create` (see below).
- **Ready for delivery** — an open bead marked `stage:ready` (`bd set-state <id> stage=ready`).
  This is the line between a raw capture and work the delivery track can pull.
- **Resolved** — a **closed** bead. The close-reason says whether it was delivered or dropped
  (`bd close <id> --reason "wontfix: …"`).

`bd ready` + dependencies + epics drive the work directly. The delivery track pulls beads that are
both unblocked (surfaced by `bd ready`) and marked `stage:ready`.

## When a skill says "publish to the issue tracker" / "create an issue"

Capture into beads with `bd create` — there is no `bd q` here, and never `gh issue create`. A
capture holds the context you have *at the moment it surfaces*, so it carries a body, not just a
title:

- **Title** — a one-line summary (a few words, not a paragraph; ~80 chars is the target, 500 the
  hard cap). It's a pointer, not the content.
- **Body** — the reasoning, evidence, and options in `-d` (or `--stdin` / `--body-file -` for a
  multi-line dump; no length limit). Add `--silent` for just the ID.

```bash
bd create "presort agent isn't a reachable subagent_type" \
  -d "seed says 'dispatch the presort agent' but it's not a registered Agent-tool type;
options: wire it into the registry, or invoke via general-purpose with inlined instructions." \
  --silent
```

Don't cram the dump into the title.

## When a skill says "fetch the relevant ticket"

`bd show <id>`. The user normally passes the bead ID directly.

## When a skill says "break this into issues" (e.g. /to-issues)

`bd create` one bead per vertical slice, wire dependencies with `bd dep`, group into an epic where
useful, and mark each ready slice `stage:ready`. There is no PRD-to-self and no separate promotion
step — the bead *is* the work item.

## Triage state

See `docs/agents/triage-labels.md` for how the canonical triage roles map onto beads states and
close-reasons.
