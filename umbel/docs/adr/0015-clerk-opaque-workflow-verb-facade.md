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
- **Operational contracts (every verb, asserted verbatim in bats — including the failure paths).**
  Surfaced by the small-model delivery experiment on unit dotfiles-dft.1 (History), where two
  independent implementations both passed all seven acceptance criteria yet diverged on behaviours
  the criteria never pinned — the signature of an underspecified contract, not a coding slip:
  - **Exit-code taxonomy, one meaning each**: `0` success; `1` `doctor` found problems (below);
    `2` usage error / unknown verb / bad-or-missing id (roster or corrected invocation printed);
    `3` a known verb not implemented in this generation; `4` `.clerk` unresolvable (missing /
    invalid / not in a git repo); `5` a backend command (`bd`/`gh`) failed or a mutation could not
    be confirmed. Dispatch distinguishes unknown (`2`) from not-yet-implemented (`3`) — a grammar
    error is not a generation gap; and a broken backend (`5`) from a caller who named a
    non-existent unit (`2`) — "the tracker is down" is not "you passed a bad id". `1` is scoped to
    `doctor`'s health check; every other verb signals operational failure through `5`, never `1`.
  - **`doctor` is a health check, not a diagnostic that always succeeds**: it exits `0` iff every
    check passes and non-zero (`1`) if any fails. This is the contract the zero-token systemd-timer
    caller depends on — a timer can only alert on a non-zero exit; a `doctor` that always exits `0`
    is silent on exactly the failures it exists to catch.
  - **Mutations self-verify before reporting success**: any state-changing action (`doctor --fix`
    writing `.clerk`, `claim` creating the branch/worktree, `capture` filing) confirms its effect
    landed before printing a success line, and on failure exits non-zero with a prescriptive
    message — it never prints `[ ok ]` / "written" over a failed write. A false success dead-ends
    the dispatch → `doctor` → dispatch recovery loop.
  - **Error text is prompt engineering**: every refusal prescribes the next verb, names the
    resolved path where one is at issue, and (for usage errors) shows the corrected invocation.
    Printed output is load-bearing — the agent's next action follows it.
  - **Output discipline**: 16-color ANSI only (30–37 / 90–97, bold/reset; never `38;5` / `38;2`).
    Colour is suppressed when the stream is not a TTY or `NO_COLOR` is set — the refusal / roster /
    `doctor` strings are parsed downstream and must never carry escape sequences into a pipe or log.

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

## History

- 2026-07-06: operational-contracts bullet added (exit-code taxonomy, `doctor`-as-health-check,
  mutation-self-verify, non-TTY/`NO_COLOR` output discipline). Surfaced by the small-model delivery
  experiment on unit dotfiles-dft.1 — a fable baseline and a sonnet-implement/haiku-verify arm both
  passed all seven acceptance criteria and shellcheck, yet diverged on `doctor`'s exit code
  (health-check `1` vs always-`0`) and one shipped a `doctor --fix` that printed success over a
  failed write. When two competent implementations of one spec diverge on a load-bearing behaviour,
  the spec underspecified a *contract* — so it is written down here rather than left to per-unit
  criteria (which cannot enumerate every failure path). The neutral referee confirmed both
  behaviours; the cost/quality data and the resulting model-tier policy live in the epic
  dotfiles-dft experiment note.
- 2026-07-07: taxonomy extended with exit `5` (a backend command failed, or a mutation could not be
  confirmed) and not-found folded into `2` (a non-existent id is a bad-id usage error, like a
  missing one). Surfaced delivering unit dotfiles-dft.2 (the inbox verbs are the first to invoke
  `bd`/`gh`): the review caught backend failures returning `1`, which collides with `doctor`'s `1`.
  Same contracts-not-instances move as the row above — decided once here, not per verb.
