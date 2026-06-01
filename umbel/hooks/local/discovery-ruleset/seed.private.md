# Discovery workflow — this is a PRIVATE repo

You run the **discovery** track here: turn raw input into a ready backlog. Follow this procedure.

## Standing rules
- **Capture is ambient.** The moment any idea, bug, or follow-up appears — yours or surfaced mid-task — run `bd q "…"`. No triage, no ceremony, no asking first. Don't rationalize skipping it: "too small", "I'll remember", "I'll fix it inline" are all wrong — `bd q` it and move on. An **open** bead is in the inbox (untriaged); a **closed** bead is triaged-out, its close-reason recording its fate.
- **beads is the backlog.** `bd ready` + dependencies + epics drive the work directly. There is no GitHub issue tracker here — do not create one.
- **Decisions go in `worklog.jsonl`**, committed to this repo: a terse, append-only journal of settled decisions and the alternatives you rejected.
- **The now-layer is your harness task list; recall facts live in auto-memory.** Never fold either into beads — they answer different questions.
- **At the start of every triage pass, load current state yourself** (never ask the user): `git pull`, refresh beads, and list the open inbox (`bd list --status=open`). Do this even when you think you already know the state — triaging a stale inbox produces duplicates and wrong calls.

## The loop
1. **Capture** (ambient): `bd q "…"` as above.
2. **Pre-sort** (optional): dispatch the `triage-presort` agent over `bd list --status=open` to cluster duplicates and propose type/priority. It only proposes — you decide.
3. **Triage** each open bead: keep or drop.
4. **Prep the keepers**: groom in place — set priority, wire dependencies (`bd dep`), group into epics — until the bead is `bd ready`. No PRD-to-self, no promotion step.
5. **Drop the rest**: `bd close <id> --reason "wontfix: …"`.

Sharpening tools available throughout prep: `grill-me` / `grill-with-docs` (stress-test a design, capture the decision), `zoom-out` (higher-level view), `prototype` (de-risk before committing), `improve-codebase-architecture` (surface deepening work as new captures), `annotate` / `last` (feedback on a plan or a long thread), `handoff` (compact a session for the next agent).

**Output:** a `bd ready` bead. That is the input to the `delivery` track.
