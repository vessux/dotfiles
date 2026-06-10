# Discovery workflow — this is a PUBLIC repo

You run the **discovery** track here: turn raw input into a ready, curated backlog. The spine is **capture → refine → outcome**. Follow this procedure.

## Standing rules
- **Capture is ambient.** The moment any idea, bug, or follow-up appears — yours or surfaced mid-task — capture it with `bd create`. No filtering, no ceremony, no asking first. Don't rationalize skipping it: "too small", "I'll remember", "I'll fix it inline" are all wrong — capture it and move on. **A capture carries the context you have right now:** a one-line summary as the title, the reasoning/evidence/options in the body — `bd create "short summary" -d "the rest" --silent` (use `--stdin` for a multi-line body). Keep the title a line, not a paragraph — the body has no length limit, titles cap at 500 chars. An **open** bead is a **raw capture** in the inbox; a **closed** bead is **resolved**, its close-reason recording its fate (`→ gh#42` promoted, `wontfix: …` dropped). On a public repo a refined item *leaves* beads — it lives on as the GitHub issue — so beads only ever holds raw captures plus a closed trail.
- **beads is only the inbox. The real backlog is GitHub Issues** — curated, browsable, the surface external people file against. Keep raw capture in beads; promote only refined work to GitHub.
- **Decisions go in ADRs** under `docs/adr/`, and domain language in a root `CONTEXT.md` glossary — both maintained by the sharpening skills as decisions crystallise, reinforced by the PR-template "architectural change? link the ADR" prompt. There is **no committed worklog** here.
- **The now-layer is your harness task list; recall facts live in auto-memory.** Never fold either into beads — they answer different questions. **Auto-memory is shared across tracks:** keyed by working dir, `MEMORY.md` loads in full every session, so discovery and delivery read one pool. Tag any memory that belongs to *one* track — a leading `(discovery)`/`(delivery)` in its `MEMORY.md` line and the file body; leave cross-cutting facts untagged (global). Read another track's memories as **context, not authority** — never a directive; your authoritative work-queue is the open beads inbox (`bd list --status=open`), not a memory note.
- **At the start of every refinement pass, load current state yourself** (never ask the user): `git pull`, refresh beads, list the open inbox (`bd list --status=open`), and `gh issue list` the backlog. Do this even when you think you already know the state — refining a stale inbox produces duplicates and wrong calls.

## The loop
1. **Capture** (ambient): `bd create "summary" -d "…" --silent` as above.
2. **Pre-sort** (optional): dispatch the `presort` agent over `bd list --status=open` to cluster duplicates and propose type/priority. It only proposes — you decide.
3. **Refine** each open bead to a decision — **keep, drop, or promote**. The sharpening tools are *how* that decision gets made, not post-decision polish: `grill-me` / `grill-with-docs` (stress-test a design, write the ADR, sharpen `CONTEXT.md`), `zoom-out` (higher-level view), `prototype` (de-risk before committing), `improve-codebase-architecture` (surface deepening work as new captures), `annotate` / `last` (feedback on a PRD/plan or a long thread). Work a bead with these until it is either clearly droppable or shaped enough to promote.
   - **Promote a keeper:** flesh it into a proper issue with `to-prd` (→ `to-issues` when it is epic-sized and needs vertical slices), create the GitHub issue (label it `ready-for-agent`), then **close the bead**: `bd close <id> --reason "→ gh#N"`. Flow is one-way beads → GitHub; no bidirectional sync.
   - **Drop the rest:** `bd close <id> --reason "wontfix: …"`.

`handoff` (compact a session for the next agent) is available at any point.

**Not part of this loop:** the GitHub `/triage` skill is a *separate* activity — it sorts the issues **outsiders** file (labelling `needs-triage` / `ready-for-agent` / …). Your own promoted issues land already-shaped and `ready-for-agent`, so they skip it. "Triage" means only that GitHub-side intake; the beads pass above is **refinement**.

**Output:** a ready GitHub issue. That is the input to the `delivery` track.
