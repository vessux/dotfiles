---
name: discovery
description: The discovery track — capture, triage, and prep raw ideas into a ready, curated backlog. beads inbox + cherry-picked triage/PRD/grill/prototype skills. Read the body to set a repo up under the workflow it describes, then hand ready work to the delivery track. Reads the repo's visibility to pick tier; adapts the rest.
skills:
  - pocock/triage
  - pocock/to-prd
  - pocock/to-issues
  - pocock/grill-me
  - pocock/grill-with-docs
  - pocock/zoom-out
  - pocock/prototype
  - pocock/improve-codebase-architecture
  - pocock/handoff
  - pocock/setup-matt-pocock-skills
  - plannotator/annotate
  - plannotator/last
agents:
  - local/triage-presort
hooks:
  - local/discovery-ruleset
mcps:
  - local/tuidriver
---

# discovery

The front half of a **discovery → delivery** workflow. discovery turns raw input
into a *ready backlog*; the delivery track (e.g. `delivery-superpowers`) builds it. This file is both the
skill set and the playbook for setting a repo up.

The skill set is **cherry-picked across upstreams**, not a wholesale mirror: no
single vendored bundle (pocock / superpowers / plannotator) maps to one track, so
discovery lists only the capture/triage/prep skills it actually uses. Execution
skills (TDD, debugging, plan-execution, code-review) belong to the delivery track.

Prerequisite: `bd` (beads) on `PATH` (`brew install bd`). beads is a CLI the agent
calls directly — it is *not* a bundle artifact. The `local/tuidriver` MCP and the
`triage-presort` subagent ship with this bundle.

## Applying this bundle

When asked to adopt discovery in a repo: read this whole file, look at the repo's
**current** state, then set it up so it runs under the operating ruleset the bundle
injects (see *What the bundle injects* below) — using the **reasoning** to resolve
anything this file doesn't spell out. This is deliberately *not* a one-size
migration: every repo starts somewhere different (greenfield, old `*.jsonl` borklog,
beads already running stealth), so adapt, and ask when the current state is ambiguous.

One question decides the shape, and you can usually answer it yourself:
**is the GitHub repo public or private?** Check with `gh repo view --json visibility`
(or the absence of a GitHub remote → treat as private). Public visibility → public
tier; private or no remote → private tier.

Setup steps:

1. **Record the tier.** Write `public` or `private` (one line) to `.repo-visibility`
   at the repo root and **commit it**. The `discovery-ruleset` SessionStart hook reads
   this marker every session and injects the matching operating procedure — so this is
   the one step that turns the rules on. It is committed (not gitignored) so it
   resolves offline in fresh clones and sandboxes, where `gh` may be unavailable.
2. **Wire beads.** Ensure `bd` is initialized and run `bd hooks install` so beads
   syncs over the repo's own git origin (import on pull/checkout, export on push). Tune
   as close to online as beads allows. *The exact config keys (auto-commit policy,
   remote wiring, ref layout) are pinned hands-on at first setup — this file names the
   behaviour, not the knobs.*
3. **Stand up the decision record for the tier.** *public*: ensure `docs/adr/` exists
   and the PR template carries an "architectural change? link the ADR" prompt.
   *private*: ensure a committed `worklog.jsonl`.

The committed `CLAUDE.md` stays the shared, contributor-facing face and carries none
of this private workflow.

## What the bundle injects

The operating ruleset is **not** written into the repo. A SessionStart hook
(`discovery-ruleset`) injects it every session, selecting `seed.public.md` or
`seed.private.md` by the `.repo-visibility` marker. Those two files are the
authoritative, self-contained procedures — capture → triage → prep, where the backlog
and decision record live, loading current state at the start of a pass, and that the
now-layer is the harness while recall facts live in auto-memory. Read them to see
exactly what a discovery session runs under; change the rules **there**, not in this
body. The hook re-injects on `startup`, `clear`, and `compact`, so the rules survive
compaction the way project-root `CLAUDE.md` is re-read. Marker absent → the hook
injects a recipe to create it rather than guessing the tier.

## Reasoning (so you can adapt to any starting point)

- **Why beads is the inbox, not the public backlog.** A public storefront must stay
  curated; a "drop almost anything" inbox is the opposite. Keep raw capture in beads
  and promote only fleshed-out items to GitHub.
- **Why GitHub is the public backlog (not beads).** It's *reinforceable*: external
  contributors and their agents already understand GitHub Issues, file into it, and
  PRs reference it. beads is a private working tool nobody else runs.
- **Why ADRs on public, worklog on private.** A decision record only works if it
  survives multi-author contact. A private idiom (worklog, beads memory) is silently
  skipped on someone else's PR; ADRs are an industry standard you can enforce via PR
  template and review. On a solo private repo there are no other authors to reinforce
  against, so the faster worklog idiom wins — and committing it to a private repo is
  both private *and* synced for free.
- **Why the ruleset is injected, not filed in the repo.** The workflow itself (beads,
  triage, worklog) is a private idiom contributors don't run; putting it in a committed
  `CLAUDE.md` pollutes the shared face, and writing it to a separate file would drift
  per-repo and need re-seeding on every bundle change. Injecting from the bundle keeps
  one authoritative copy, versioned with the bundle, present only while the bundle is
  loaded — and the repo stays clean but for the one-line `.repo-visibility` marker. The
  marker is committed (not gitignored) so it resolves offline in any clone or sandbox;
  it carries no `umbel` in its name because it's the workflow's fact, not the tool's.
- **Why close the bead on promotion.** The bead's job is to get an idea to the
  starting line, not to track the work. Closing it the moment it becomes a GitHub
  issue means no live link to keep in sync. The close-reason preserves the trail.
- **Why the now-layer is the harness and recall is auto-memory.** beads holds
  durable, cross-session work *intent*. In-session step tracking dies with the
  session (harness tasks); recall facts/preferences are injected per session
  (auto-memory). Folding those into beads duplicates tools that already do those jobs.
