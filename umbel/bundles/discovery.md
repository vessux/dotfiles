---
name: discovery
description: The discovery track — capture and refine raw ideas into a ready backlog. beads inbox + cherry-picked refinement/PRD/grill/prototype skills. Read the body to set a repo up under the workflow it describes, then hand ready work to the delivery track. Reads the repo's visibility to pick tier; adapts the rest.
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
  - local/presort
  - local/glean
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
discovery lists only the capture/refine skills it actually uses. Execution
skills (TDD, debugging, plan-execution, code-review) belong to the delivery track.

Prerequisite: `bd` (beads) on `PATH` (`brew install bd`). beads is a CLI the agent
calls directly — it is *not* a bundle artifact. The `local/tuidriver` MCP and the
`/presort` skill (a forked, read-only refinement-pass classifier) ship with this bundle.
`local/glean` (the end-of-session impediment harvester, `/glean`) also ships here — it is
track-agnostic and lives in the base/`delivery-base` layer, dual-listed into discovery.

## Applying this bundle

When asked to adopt discovery in a repo: read this whole file, look at the repo's
**current** state, then set it up so it runs under the operating ruleset the bundle
injects (see *What the bundle injects* below) — using the **reasoning** to resolve
anything this file doesn't spell out. This is deliberately *not* a one-size
migration: every repo starts somewhere different (greenfield, old `*.jsonl` borklog,
beads already running stealth), so adapt, and ask when the current state is ambiguous.

One question decides the shape, and you can usually answer it yourself:
**is the GitHub repo public or private?** Check with `gh repo view --json visibility`:
public visibility → public tier; private or internal → private tier. **No GitHub remote
yet is not a third option** — it means *not ready to adopt the private tier*, because the
private path's beads wiring (step 2) is remote-backed. Publish the repo and add the remote
*first*, then proceed as private.

Setup steps:

1. **Record the tier.** Write `public` or `private` (one line) to `.repo-visibility`
   at the repo root and **commit it**. The `discovery-ruleset` SessionStart hook reads
   this marker every session and injects the matching operating procedure — so this is
   the one step that turns the rules on. It is committed (not gitignored) so it
   resolves offline in fresh clones and sandboxes, where `gh` may be unavailable.
   **For the `private` tier, a git remote is a prerequisite — add it before writing
   `private`** (step 2's beads wiring is remote-backed). A repo with no remote isn't
   "private, locally"; it's *not ready to adopt the private tier* — publish and add the
   remote first. Local-only beads runs, but leaves step 2 incomplete; that's not done.
2. **Wire beads — git-remote-backed via Dolt; transparent, but fork-safe.** This is the
   step people get wrong. The goal: **don't hide that the repo uses beads, but cleanly
   separate the maintainer's cross-machine DX from anything that could fight a forker's
   setup.** Commit what travels safely and is inert for others; keep local/machine-specific
   state out of git. Beads' own defaults already encode this split — follow them; don't
   invent ad-hoc overrides.

   - **Prerequisite — a git remote.** This whole step is remote-backed (Dolt syncs to the
     git origin; auto-backup enables only when a remote exists), so a remote must already
     be wired — sequenced *before* you wrote `.repo-visibility=private`. No remote → publish
     the repo and add it first; don't proceed here (or declare setup done) on a remote-less repo.
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
     unaffected. The hooks auto-**commit** Dolt locally, but — verified on this machine —
     they do **not** bridge `bd dolt pull` onto `git pull` (there is no `refs/dolt/*` fetch
     refspec) and do **not** push Dolt. So **pulls are explicit `bd dolt pull`** and the push
     side rides the `bd` shim with `dolt.auto-push` off (ADR 0013) — see the sync note below.
   - **Set your beads role — per-clone, machine-local: `git config beads.role maintainer`.**
     beads tags git operations with a role; left unset it nags and `bd doctor` flags it
     (`Fix: git config beads.role maintainer`). Set it the same way as `core.hooksPath` —
     with `git config` (machine-local), **never** in the committed `.beads/config.yaml`,
     which would foist `maintainer` on every fork. Your own clones use `maintainer`; a
     contributor who opts into beads sets `contributor`.

   *Auth/ref layout are environment-specific — confirm the push lands before relying on it.*

   **Done condition.** Step 2 is complete only when the inbox is reachable *and new captures
   keep reaching the remote*: `bd list` returns the beads inbox *and* a throwaway test capture
   **advances** `git ls-remote origin 'refs/dolt/*'` (then delete it). `ls-remote` merely *showing*
   refs proves a past push, not that today's captures still sync — that's the silent-dead-sync
   trap. The git hooks do **not** push Dolt; the remote advances via the `bd` shim's debounced
   background push after a mutating `bd` (`dolt.auto-push` is **off** — racy in embedded mode,
   ADR 0013) or a forced `bd dolt push`. Because the shim's push is debounced, give it a beat —
   or flush synchronously — before asserting the ref advanced. On a single machine remote sync is
   backup-only and optional. A repo where `.repo-visibility=private` exists but a test capture
   fails to advance the remote is **not** set up — don't claim discovery setup is done.

   *Sync is **git-style async, not real-time**: a capture/claim is a local commit on a
   per-machine **embedded** Dolt that reaches the origin's `refs/dolt/data` on push and other
   machines on an explicit pull — **a claim is not a lock**. The push side rides the **`bd`
   shim** — a debounced, crash-safe background coordinator that flushes after every mutating
   `bd` (ADR 0013); `dolt.auto-push` is **off** because in embedded mode it's racy/best-effort
   (a short-lived `bd` can exit before the push's round-trip). The receive side is **explicit
   `bd dolt pull`** (at presort/triage open and before each delivery claim) — `git pull` does
   **not** carry it (no `refs/dolt/*` fetch refspec, no bridge hook) and there is no background
   auto-pull. Concurrent delivery workers on one machine share that machine's embedded Dolt and
   so serialize locally; a shared `dolt sql-server` is an optional, reversible **devbox-internal**
   toggle for that local contention only — never the cross-machine path.*
3. **Stand up the decision record.** Both tiers record decisions the same way:
   **ADRs** under `docs/adr/` plus a root **`CONTEXT.md`** glossary, created *lazily*
   by the sharpening skills (`grill-with-docs`, `improve-codebase-architecture`) when
   there's a decision or a term worth recording — so there's nothing to pre-create.
   *public* additionally: ensure the PR template carries an "architectural change?
   link the ADR" prompt. **No `worklog.jsonl` on either tier**.
4. **Generate the agent docs the bundled skills read.** Run `/setup-matt-pocock-skills`
   (shipped in this bundle) to scaffold `docs/agents/{issue-tracker,triage-labels,domain}.md`
   plus the `## Agent skills` block in `CLAUDE.md`/`AGENTS.md`. The bundled `to-prd`,
   `to-issues`, and `triage` skills read these for the tracker, triage vocabulary, and domain
   layout, and nag (or run with the wrong context) when they're missing. One adaptation: when
   the skill asks where issues live, the answer is **beads, not its GitHub default** — describe
   the beads inbox via the "Other" option (private tier: beads *is* the backlog; public tier:
   beads is the inbox feeding the GitHub backlog), and map triage onto this bundle's `stage:*`
   states rather than the canonical GitHub labels.

**Migrating an existing `*.jsonl` backlog (borklog):** import each item into beads
(`bd create … --external-ref <old-id>`), **then keep the old `backlog.jsonl` /
`worklog.jsonl` as a gitignored archive — never `rm` the only copy.** Distill any
existing worklog into ADRs regardless of tier (both tiers record decisions as
ADRs + `CONTEXT.md` now).

The committed `CLAUDE.md` stays the shared, contributor-facing face and carries none of
this private workflow. **Do not put the workflow's process in `CLAUDE.local.md` either** —
the operating ruleset is *injected* (see below), so a pointer there just drifts from the
bundle. Retire any prior process rules in `CLAUDE.local.md` (e.g. an old borklog block);
don't replace them with a new pointer.

## What the bundle injects

The operating ruleset is **not** written into the repo. A SessionStart hook
(`discovery-ruleset`) injects it every session, selecting `seed.public.md` or
`seed.private.md` by the `.repo-visibility` marker. Those two files are the
authoritative, self-contained procedures — capture → refine → outcome, where the backlog
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
- **Why ADRs (+ `CONTEXT.md`) on both tiers.** A decision record only works if it
  survives multi-author contact, and ADRs are an industry standard you can enforce via
  PR template and review. ADRs plus a `CONTEXT.md` glossary are also exactly what the
  sharpening skills (`grill-with-docs`, `improve-codebase-architecture`) already produce.
  So both tiers use them, and only the *backlog* differs by tier (GitHub Issues vs
  beads). The earlier private-only `worklog.jsonl` idiom was dropped — it bought little
  over the proven ADR + glossary pair and split the two tiers needlessly.
- **Why the ruleset is injected, not filed in the repo.** The workflow itself
  (beads-as-inbox, the refinement pass, the bd-driven backlog) is a private idiom
  contributors don't run; putting it in a committed
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
