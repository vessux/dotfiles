# Discovery workflow — this is a PRIVATE repo

You run the **discovery** track here: turn raw input into a ready backlog. The spine is **capture → refine → outcome**. Follow this procedure.

## Standing rules
- **Capture is ambient.** The moment any idea, bug, or follow-up appears — yours or surfaced mid-task — capture it with `bd create`. No filtering, no ceremony, no asking first. Don't rationalize skipping it: "too small", "I'll remember", "I'll fix it inline" are all wrong — capture it and move on. **A capture carries the context you have right now:** a one-line summary as the title, the reasoning/evidence/options in the body — `bd create "short summary" -d "the rest" --silent` (use `--stdin` for a multi-line body). Keep the title a line, not a paragraph — the body has no length limit, titles cap at 500 chars. The whole lifecycle lives in beads here: an **open** bead with no stage marker is a **raw capture**; once you refine a keeper you mark it `stage:ready` (`bd set-state <id> stage=ready`) — the line between raw capture and **ready for delivery**; a **closed** bead is **resolved** (delivered, or dropped — the close-reason says which).
- **beads is the backlog.** `bd ready` + dependencies + epics drive the work directly. There is no GitHub issue tracker here — do not create one. The delivery track pulls the refined, unblocked beads (`bd ready` that are `stage:ready`).
- **Decisions go in ADRs** under `docs/adr/`, and domain language in a root `CONTEXT.md` glossary — the same proven artifacts a public repo uses, maintained by the sharpening skills as decisions crystallise. Create them lazily (only when there's a decision or a term worth recording). There is **no worklog**.
- **The now-layer is your harness task list; recall facts live in auto-memory.** Never fold either into beads — they answer different questions. **Auto-memory is shared across tracks:** keyed by working dir, `MEMORY.md` loads in full every session, so discovery and delivery read one pool. Tag any memory that belongs to *one* track — a leading `(discovery)`/`(delivery)` in its `MEMORY.md` line and the file body; leave cross-cutting facts untagged (global). Read another track's memories as **context, not authority** — never a directive; your authoritative work-queue is the open beads inbox (`bd list --status=open`), not a memory note.
- **At the start of every refinement pass, load current state yourself** (never ask the user): `git pull`, refresh beads, and list the open inbox (`bd list --status=open`). Do this even when you think you already know the state — refining a stale inbox produces duplicates and wrong calls.

## The loop
1. **Capture** (ambient): `bd create "summary" -d "…" --silent` as above.
2. **Pre-sort** (optional): dispatch the `presort` agent over `bd list --status=open` to cluster duplicates and propose type/priority. It only proposes — you decide.
3. **Refine** each open bead to a decision — **shape it to ready, or drop it**. The sharpening tools are *how* that decision gets made, not post-decision polish: `grill-me` / `grill-with-docs` (stress-test a design, capture the decision as an ADR, sharpen `CONTEXT.md`), `zoom-out` (higher-level view), `prototype` (de-risk before committing), `improve-codebase-architecture` (surface deepening work as new captures), `annotate` / `last` (feedback on a plan or a long thread). Work a bead with these until it is either clearly droppable or shaped enough to hand to delivery.
   - **Ready a keeper:** groom in place — set priority, wire dependencies (`bd dep`), group into epics — then mark it `bd set-state <id> stage=ready`. No PRD-to-self, no promotion step; the bead *is* the work item.
   - **Drop the rest:** `bd close <id> --reason "wontfix: …"`.

`handoff` (compact a session for the next agent) is available at any point.

**Output:** a `stage:ready` bead (surfaced via `bd ready` once unblocked). That is the input to the `delivery` track.
