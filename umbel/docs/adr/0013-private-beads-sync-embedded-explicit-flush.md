---
status: accepted
---

# Private-tier beads sync: explicit pulls + a crash-safe `bd`-shim push, server demoted to a devbox-internal toggle

The private beads inbox syncs cross-machine from per-machine **embedded** Dolt DBs, with
`dolt.auto-push` **off**. **Pulls are explicit** (freshness-before-action, can't be debounced):
at presort/triage open, and immediately before a delivery Claim. **Pushes ride a `bd` shim** — a
debounced, nonblocking, **crash-safe background coordinator** that flushes after every mutating
`bd`, so captures sync with zero operating-rule discipline and no git hooks. A **synchronous push
is used only where a background process won't survive or confirmation is required** — after the
correctness-critical writes of an automated devbox delivery job (`claim`/`close`), and as the
sync-works verification point. A shared `dolt sql-server` is demoted to an optional, reversible
**devbox-internal** toggle.

## Context

Target deployment: **discovery runs interactively on a Mac, automated delivery runs on a devbox**
— concurrent, bidirectional writers on one inbox, no human on the devbox side. Two empirical
findings (dotfiles-sp0) forced the question: embedded `dolt.auto-push=true` is **racy/best-effort**
(a short-lived `bd` process can exit before the push's network round-trip — identical `bd create`s
disagreed; `close`/`delete` didn't push), and beads' built-in git hooks auto-**commit** Dolt but
never **push** it. Also verified on this machine: `git pull` does **nothing** for the inbox — no
`refs/dolt/*` fetch refspec, and the bridge hook isn't installed — so pulls must be explicit
`bd dolt pull`, not a `git pull` side effect.

Two facts collapse the architecture choice:

- **Discovery never claims.** Capture / ready / drop are discovery actions; the only
  mutual-exclusion-sensitive op — the Claim — happens only on devbox, among devbox-local workers
  that share one embedded Dolt and so serialize locally. The claim atomicity ADR 0011 relies on
  holds *within one Dolt instance*. So there is **no Mac-vs-devbox distributed-lock requirement**.
- **Offline discovery is required**, and a `dolt sql-server` client holds no local copy — server
  mode and offline are contradictory connection models. Offline forces Mac onto embedded+async;
  a server could then only ever serve devbox's own workers.

So the cross-machine hazard is **staleness, not mutual exclusion** — recoverable (pull-before-act;
Dolt merges divergent commits), never corrupting.

The push mechanism was then de-risked with a throwaway prototype (dotfiles-zao). A naive
`mkdir`-lock + pid-reaping coordinator is **racy and wedges** (a SIGKILLed holder never runs its
cleanup, orphaning the lock). The fix — verified 6/6 incl. crash-recovery — is a **kernel
`flock(2)`** held by the coordinator for its life, acquired via `perl` (portable; macOS ships no
`flock(1)`) with close-on-exec cleared so the lock survives `exec`. The kernel releases it on any
death, so there's no stale artifact and no reaping race.

## Decision

- **`dolt.auto-push = false`** — it is racy; the shim drives pushing instead.
- **Per-machine embedded Dolt.** Source of truth is local; the git origin's `refs/dolt/data` is the sync point.
- **Pulls are explicit `bd dolt pull`** (never a `git pull` side effect): at **presort/triage
  open** (the existing "load current state" step), and **immediately before each delivery Claim**
  (guards against a stale ready-set).
- **Pushes via the `bd` shim** (dotfiles-zao): a wrapper on `PATH` (`~/.config/bin`, per ADR 0001)
  that, after a mutating `bd`, marks work owed and (re)spawns a **detached, debounced, `flock`-guarded
  background coordinator**. It coalesces bursts into one push, survives the triggering shell's exit,
  and is crash-safe. This carries the high-frequency Mac discovery captures with no discipline.
- **Synchronous push, scoped — not a blanket session-end ritual.** The detached coordinator already
  delivers eventually for the persistent Mac shell, so a synchronous flush is *redundant there*. It
  is used where a background process **won't survive** or where **confirmation is needed**:
  - After the correctness-critical writes of an **automated devbox delivery job** (`claim`, and
    especially `close`): the harness tears down the job's whole process tree at exit (container /
    cgroup SIGKILL), which `setsid` does **not** escape — a pending debounced push would die with
    the job, so the final state-change must push synchronously *before* the job exits.
  - As the **verification point** that the remote ref actually advanced (sp0's done-condition).
- **No flush-on-`git push` hook** — most captures don't coincide with a code push, so a hook would
  silently miss them.
- **`dolt sql-server` demoted** to an optional, reversible **devbox-internal** toggle — adopt it
  only if/when devbox runs concurrent delivery workers that contend on its local embedded Dolt. It
  is never part of the cross-machine path.

## Considered options

- **Shared `dolt sql-server` as the cross-machine store** — rejected: a server client keeps no
  local copy, so it cannot satisfy offline discovery; and the concurrency it would serialize (the
  Claim) is already serialized devbox-locally.
- **Keep `dolt.auto-push=true`** — rejected: empirically racy (sp0), not a reliable default.
- **Explicit `bd dolt push` at named lifecycle points** (the earlier form of this decision) —
  superseded by the shim: correct but leans on operating-rule discipline at every write site; the
  shim removes that for the high-frequency push side. Explicit *synchronous* push survives only in
  the scoped teardown/verification role above.
- **`mkdir`-lock + pid-reaping coordinator** — rejected (prototype): racy under bursts and wedges
  permanently if the holder is SIGKILLed. The `flock(2)` guard is crash-safe by construction.
- **Blanket synchronous flush at every session end** — rejected: redundant given the surviving
  detached coordinator, and adds latency to the interactive path for no gain.
- **Flush via a custom `git push` hook** — rejected: captures rarely coincide with a code push.

## Consequences

- The shim (dotfiles-zao) must be built and installed on **both** machines; it is the lead work,
  and sp0 (config `auto-push false` + encoding the pull points and the scoped synchronous-push
  points in the discovery/delivery seeds + correcting the stale bundle docs) sits on top of it.
- **The shim must win `PATH`, not merely sit on it.** It only shadows the real `bd` while
  `~/.config/bin` *precedes* the real binary (e.g. `/usr/local/bin`). `.zshenv` prepends it for
  non-interactive callers, but an interactive shell then rebuilds `PATH` with the system defaults
  and tool managers (mise) ahead of it — dropping `~/.config/bin` behind `/usr/local/bin` and
  silently un-shadowing the shim; with `auto-push` off that means *nothing* pushes. `.zshrc`
  re-prepends `~/.config/bin` last (after mise) to fix it. zao's hand-off assumed "on `PATH` in
  `.zshenv`" sufficed — it doesn't for interactive / Claude Code shells. Worse, a session's `PATH`
  is a **snapshot captured at launch**: a session launched from a context predating this `.zshrc`
  fix carries a stale `PATH` where the shim isn't first, silently bypassing `BD_SHIM_SYNC`
  (reloading the session refreshes the snapshot). The delivery close therefore uses an explicit
  `bd dolt push` — which pushes regardless of shim ordering — plus the `ls-remote` confirm as
  backstop, rather than trusting `BD_SHIM_SYNC` (dotfiles-y7m).
- The discovery bundle's sync note is wrong on two counts now — it calls `auto-push` "the
  cross-machine default" and claims `git pull` bridges `bd dolt pull` — and is corrected to this model.
- Dead-agent stranded claims remain — automatic stale-claim reclaim is tracked separately
  (dotfiles-dnq).
- Offline Mac writes queue locally and resync (with Dolt merge) on reconnect; a hard shutdown
  mid-debounce loses only the *remote* copy of those captures (local is intact; syncs next session).

## History

- 2026-06-29: created. Chose async-embedded over `sql-server` (discovery never claims → no
  distributed lock; offline discovery → embedded), with `auto-push` off and **explicit
  `bd dolt push` at named lifecycle points** as the push mechanism.
- 2026-06-29: push mechanism changed to the **`bd` shim** after `/prototype` (dotfiles-zao) proved
  a crash-safe, portable, `flock(2)`-guarded debounced coordinator viable (6/6, incl. SIGKILL →
  no-wedge and burst-after-crash → one winner). The shim removes the per-write-site discipline the
  explicit form required. `flush_now` (synchronous push) was simultaneously narrowed from a blanket
  session-end backstop to the scoped teardown/verification role — the surviving detached coordinator
  makes it redundant on the persistent Mac shell.
- 2026-06-30: delivered (dotfiles-sp0). Delivery found the shim was installed but **shadowed** —
  `~/.config/bin` lost `PATH` ordering to `/usr/local/bin` in interactive / Claude Code shells, so
  `bd` resolved to the real binary and *nothing* would push once `auto-push` went off. Fixed by
  re-prepending `~/.config/bin` in `.zshrc` (the last `PATH` writer) so the shim wins everywhere
  (see the PATH consequence above). Also flipped `auto-push` off, encoded the explicit-pull and
  scoped synchronous-push points into the discovery+delivery seeds, and corrected the stale bundle
  sync notes.
- 2026-07-01: dotfiles-y7m — the 9sq close's non-advance was a **stale-session PATH snapshot**
  (shim bypassed, `BD_SHIM_SYNC` no-op), not a mechanism failure; verified the shim pushes
  synchronously in a fresh session. Hardened the delivery close to an explicit `bd dolt push`
  (stale-proof) + the `ls-remote` confirm, promoting the recovery memory into the seed.
