---
status: accepted
---

# Clerk: an opaque workflow-verb facade owns all mechanism — built, not adopted

Workflow mechanism (claim atomicity, sync discipline, finish sequencing) lived in seed prose and
auto-memories that agents re-read, re-obey, and eventually skip (dotfiles-b6r); fixes landed as
more prose (y7m, ys5, the skip-worktree/dirty-checkout memory cluster). We move every menial,
deterministic step behind **`clerk`** — a single dispatcher in repo `bin/`, stowed like the `bd`
shim — and the agent speaks workflow verbs. The split is **judgment vs paperwork**: the agent
decides *which* verb and authors anything requiring judgment (PR bodies, promotion titles, return
reasons); the clerk executes mechanism exactly, in code that cannot drift from itself.

## Decision

- **Grammar is noun-scoped by collection (place)**: `inbox` (unrefined pool) and `backlog` (ready
  pool). Object-type nouns break under promote=flow; ID-shape dispatch couples to backend token
  formats — both rejected in the session-1 stress test (epic dotfiles-dft).
- **Verb roster**: `capture "<title>" [--stdin|--impediment]`; `inbox list|show|dups|ready|drop|pregrill`;
  `backlog next|show|claim|release|return|submit|finish`; `sync`; `doctor`; `glean`.
- **Opacity (hard ban, layered)**: skills, bundles, hooks, seeds, and injected instructions never
  name beads/`bd` — the backing store is the clerk's private business. Agent *runtime* discovery of
  `bd` is tolerated (reads harmless; writes self-punishing — they reintroduce solved bugs like the
  stale close ADR 0013 fixed) and signals a missing verb (an Impediment). The unattended tier will
  make the ban structural via the permission allowlist (dotfiles-220). Raw `bd` grooming
  (`dep`/`update`/`epic`) stays legal only in operator docs and live human sessions; the first
  *skill* needing grooming vocabulary is the trigger to mint the clerk verb.
- **One keyless binary, four callers**: agent in attended session; agent in job (clerk detects job
  context itself — absorbs the BD_SHIM_SYNC seed clauses); **no agent at all** — the
  authorship-free verbs (`sync`, `doctor`) are schedulable as a plain systemd timer, zero tokens;
  human terminal (`clerk backlog next` is `nextdelivery`'s successor as a first-class human
  surface; `--explain` prints underlying commands + ADR pointer).
- **Three keys, zero verb ACLs** — autonomy is dialed at boundaries the human controls, never in
  clerk code: (K1) merge key = review-required branch protection (ADR 0016); (K2) initiation key =
  the human starts sessions; (K3) in-session key = harness permission allowlist (reads, `capture`,
  `claim` free; `submit`/`finish` prompt-gated initially).
- **Three loops, three owners**: inner (red check → fix → push → `finish`) agent-owned in-session;
  session loop (claim → build → submit → finish) owned by the bundle's operating rules; outer loop
  (launching unattended sessions) **deferred to a future epic** — this epic is attended-first,
  unattended-ready.
- **Hook roster = one hook**: SessionStart (seed-inject + kick `clerk glean`). A Stop-hook claim
  guard was rejected (fires every turn mid-build; no honest mount point) — the `sync` sweep is the
  sole abandonment net. A SessionEnd glean hook was rejected (doesn't fire on crashes/kills —
  leaky exactly on messy sessions).
- **`clerk glean` is a watermark sweep**: per-transcript-file line-offset watermark (offsets, not
  timestamps: exactly-once, no gaps), spawns the judgment fork per unharvested chunk, advances the
  watermark only after captures file successfully, `flock`-guarded single instance, fully async.
  Cursor state in `~/.local/state/clerk/`.
- **Reconciler (`finish`/`sync`)**: one stateless function, two schedulers — finish-eager as the
  delivery session's last act, sync-sweep over all open claims (absorbs dotfiles-dnq stale-claim
  reclaim). **The sweep never authors** — it executes authorship-free phases and files reports for
  judgment-needing states. `finish` is non-blocking by default (`--watch` opt-in wraps
  `gh pr checks --watch`); it detects merge via **PR state only, never ancestry** (squash orphans
  branch commits). `submit` is once per unit; iteration repeats `finish`.
- **Merge method = squash**: one unit = one PR = one commit, unit id in the subject, criteria
  evidence in the body — `git log` is the delivery record glean audits.
- **Offline claim = attended-only degraded mode**: proceed with a quantified LOCAL-ONLY warning;
  the canonical branch is the CAS at reconnect (second push rejected → collision detected, never
  silent). Job contexts refuse offline claims.
- **Error text is prompt engineering**: every refusal prescribes the next verb. Printed output is
  load-bearing (the agent's next action follows it) — tested like exit codes. 16-color ANSI only.

## Considered options

- **Adopt beads formulas/molecules or Gas Town** (verified: local `bd` 1.0.4 ships
  `formula`/`cook`/`mol`/`gate`/`merge-slot`; zero formulas in use) — rejected: formulas define the
  *shape of work* (bead-DAG templates), not mechanism; Gas Town is a multi-agent runtime whose
  Refinery replaces the trust fabric with its own merge queue, killing the gh backlog dispatch and
  the branch-protection gate bet. Steals taken instead: `bd ready` ≈ private `backlog next`;
  `bd --readonly` wraps clerk read verbs (structural fork read-only); `bd gate`/`merge-slot` noted
  as future serialization primitives. Re-evaluate Gas Town only if the end-state becomes
  multi-agent fleets; opacity keeps `gt` adoptable as a binding later.
- **Five top-level commands instead of a dispatcher** — rejected: `sync`/`doctor` are too generic
  for PATH; `--explain` and doctor version-parity want one entry point.
- **Umbel-derived or flow-family names** — rejected: umbel is a delivery mechanism, not a sibling
  project; `deskflow` collides with the Synergy fork; "task"/"workflow" pollute agent priors
  (harness Task tools, `gh workflow`). `clerk` is the English word fusing desk + menial labor.
- **Role→backend manifest now** — deferred until a third binding exists; dispatch is two hardcoded
  presets riding the `.clerk` marker (ADR 0017). Interface now, generality lazily (ADR 0010).

## Consequences

- **The bundle generation is re-authored, not migrated**: new `clerk-discovery`,
  `clerk-delivery-base`, `clerk-delivery-superpowers` speak clerk from birth; the old generation
  (three workflow manifests + personal variants, `delivery-base-ruleset` hook, both tier seeds,
  presort skill) is **frozen as-is** and retired later. Freeze boundary is wording, not tooling —
  wording-neutral tools (grill-with-docs, plannotator, tuidriver, glean mechanics) are shared.
  Cutover is per-repo re-pin; rollback is re-pinning the old bundle.
- Pre-sort's successor is decision-free with one write verb (`inbox pregrill`, ADR 0016); the
  inbox noun definition (open minus `stage:ready`) moves from skill prose into clerk code.
- `nextdelivery` and its dead `umbel adopt` hint dissolve (`clerk backlog next` / `clerk doctor`);
  `land` and the dirty-shared-checkout hazard class dissolve with worktree-per-claim; the
  delivery-finish memory cluster (user-pushes-main, worktree-discard, skip-worktree, dirty-checkout)
  retires — enforced by structure instead of remembered (dotfiles-w0x).
- `CLAUDE.md`'s "issues live in beads" line is Layer-1 text and becomes clerk wording;
  `docs/agents/issue-tracker.md` remains the one operator doc allowed to name beads.
