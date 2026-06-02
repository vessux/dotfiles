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
2. **Wire beads — git-remote-backed via Dolt; transparent, but fork-safe.** This is the
   step people get wrong. The goal: **don't hide that the repo uses beads, but cleanly
   separate the maintainer's cross-machine DX from anything that could fight a forker's
   setup.** Commit what travels safely and is inert for others; keep local/machine-specific
   state out of git. Beads' own defaults already encode this split — follow them; don't
   invent ad-hoc overrides.

   - **Normal mode, not `--stealth`.** Stealth hides beads, sets `no-git-ops: true`, and
     **skips wiring the Dolt remote** — wrong for a shared/public repo. Being open about
     beads is fine; fork-safety comes from *which artifacts* are committed (below), not
     from hiding.
   - **The Dolt DB is the source of truth, synced Dolt-natively** to a Dolt remote that is
     the git origin (`refs/dolt/data`) — never by committing issue data:
     ```
     bd dolt remote add origin git+https://github.com/<owner>/<repo>.git   # match your git auth (https/ssh)
     bd dolt push                                                          # → refs/dolt/data; verify: git ls-remote origin 'refs/dolt/*'
     ```
     A clone or new machine runs **`bd bootstrap`** to pull the inbox.
   - **Commit vs ignore — keep beads' defaults:**
     - *Committed* (beads tracks these by default): `.beads/config.yaml`,
       `.beads/metadata.json`, `.beads/.gitignore`, and the **`.beads/hooks/` shims**. The
       shims are portable and **no-op without `bd` installed** (`command -v bd`), activating
       only through a *local, machine-absolute* `core.hooksPath` — so they travel to forks
       but never run for, or fight, a contributor who doesn't use beads.
     - *Gitignored* (local / machine-specific / churny): the Dolt DB
       `.beads/embeddeddolt/` + credential (beads' own `.beads/.gitignore` handles these),
       plus **`.beads/issues.jsonl`** (a ~60s-rewritten export — NEVER the git backing) and
       **`.beads/interactions.jsonl`** (a raw agent-audit log not worth auto-publishing).
       Also `bd config set export.git-add false` so the export is never auto-staged.
   - **Hooks: `bd hooks install --beads`** (not the bare default, which lands in
     `.git/hooks/`). `--beads` writes the shims to `.beads/hooks/` and points
     `core.hooksPath` at that absolute path, which is **shared across `git worktree`
     checkouts** — essential because delivery methods (e.g. superpowers) routinely spin up
     worktrees, and every worktree must reach the one shared inbox and run the same hooks.
     `core.hooksPath` is local config, so this stays per-machine opt-in; forks are
     unaffected. Hooks automate `bd dolt push/pull` alongside `git push`/`git pull`.

   *Auth/ref layout are environment-specific — confirm the push lands before relying on it.*

   *Sync is **git-style async, not real-time**: a capture/claim is a local commit that
   reaches the remote on push and other machines on pull — **a claim is not a lock**.
   `dolt.auto-commit=on` (default) + these hooks automate that at git push/pull boundaries,
   which is sufficient for a solo maintainer across machines. `dolt.auto-push` (newer bd)
   only adds per-command pushing, is single-writer-only, and adds remote churn — skip it
   unless capture-only sessions (no code push) must self-sync. There is no background
   auto-pull in any version; the receive side is always `git pull`/`bd dolt pull`. For a
   **concurrent multi-agent / multi-machine** flow this single-writer model is the wrong
   fit — switch beads to a shared `dolt sql-server` (server mode: `bd init --server` /
   `bd dolt start`) per the beads docs.*
3. **Stand up the decision record for the tier.** *public*: ensure `docs/adr/` exists
   and the PR template carries an "architectural change? link the ADR" prompt.
   *private*: ensure a committed `worklog.jsonl`.

**Migrating an existing `*.jsonl` backlog (borklog):** import each item into beads
(`bd create … --external-ref <old-id>`), **then keep the old `backlog.jsonl` /
`worklog.jsonl` as a gitignored archive — never `rm` the only copy.** Distill a public
repo's worklog into ADRs; freeze a private repo's worklog in place.

The committed `CLAUDE.md` stays the shared, contributor-facing face and carries none of
this private workflow. **Do not put the workflow's process in `CLAUDE.local.md` either** —
the operating ruleset is *injected* (see below), so a pointer there just drifts from the
bundle. Retire any prior process rules in `CLAUDE.local.md` (e.g. an old borklog block);
don't replace them with a new pointer.

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
