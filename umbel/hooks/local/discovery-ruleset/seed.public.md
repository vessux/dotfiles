# Discovery workflow — this is a PUBLIC repo

You run the **discovery** track here: turn raw input into a ready, curated backlog. Follow this procedure.

## Standing rules
- **Capture is ambient.** The moment any idea, bug, or follow-up appears — yours or surfaced mid-task — run `bd q "…"`. No triage, no ceremony, no asking first. Don't rationalize skipping it: "too small", "I'll remember", "I'll fix it inline" are all wrong — `bd q` it and move on. An **open** bead is in the inbox (untriaged); a **closed** bead is triaged-out, its close-reason recording its fate (`→ gh#42`, `wontfix: …`).
- **beads is only the inbox. The real backlog is GitHub Issues** — curated, browsable, the surface external people file against. Keep raw capture in beads; promote only fleshed-out work to GitHub.
- **Decisions go in ADRs** under `docs/adr/`, reinforced by the PR-template "architectural change? link the ADR" prompt. There is **no committed worklog** here.
- **The now-layer is your harness task list; recall facts live in auto-memory.** Never fold either into beads — they answer different questions.
- **At the start of every triage pass, load current state yourself** (never ask the user): `git pull`, refresh beads, list the open inbox (`bd list --status=open`), and `gh issue list` the backlog. Do this even when you think you already know the state — triaging a stale inbox produces duplicates and wrong calls.

## The loop
1. **Capture** (ambient): `bd q "…"` as above.
2. **Pre-sort** (optional): dispatch the `triage-presort` agent over `bd list --status=open` to cluster duplicates and propose type/priority. It only proposes — you decide.
3. **Triage** each open bead: keep or drop.
4. **Prep the keepers**: flesh a kept bead into a proper issue with `to-prd` (→ `to-issues` when it is epic-sized and needs vertical slices), create the GitHub issue, then **close the bead**: `bd close <id> --reason "→ gh#N"`. Flow is one-way beads → GitHub; no bidirectional sync.
5. **Drop the rest**: `bd close <id> --reason "wontfix: …"`.

Sharpening tools available throughout prep: `grill-me` / `grill-with-docs` (stress-test a design, write the ADR), `zoom-out` (higher-level view), `prototype` (de-risk before committing), `improve-codebase-architecture` (surface deepening work as new captures), `annotate` / `last` (feedback on a PRD/plan or a long thread), `handoff` (compact a session for the next agent).

**Output:** a ready GitHub issue. That is the input to the `delivery` track.
