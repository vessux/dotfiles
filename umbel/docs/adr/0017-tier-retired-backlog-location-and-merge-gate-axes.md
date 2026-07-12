---
status: accepted
---

# Tier retired: backlog-location and merge-gate are independent axes; `.clerk` is the manifest v0

The public/private "tier" conflated two independent policies, and this repo falsified the wording
itself: its `.repo-visibility` marker says `private` while the GitHub remote is public — tier was
always policy, never a remote fact. The real axes are **backlog location** (where the ready pool
lives: `bd stage:ready` vs `gh` issues `ready-for-agent`) and **merge gate** (the autonomy dial:
review-required vs auto-merge-on-green). They get opposite storage treatments on one principle —
**policy lives where its enforcement lives**.

## Decision

- **Backlog location = a committed marker, `.clerk`, at the repo root** — dispatch must be
  deterministic and offline-capable. One key for now (`backlog: bd|gh`), and the file is the
  **manifest v0**: when a third binding arrives (jira/linear/gt; promote and claim styles), roles
  become new keys in an existing file, not a migration (ADR 0010's interface-now instinct;
  ADR 0015's presets ride this key).
- **The marker is strict, and ambiguity is refused, never resolved.** A valid `.clerk` is a single
  directive line (surrounding whitespace and `#`-comment lines tolerated). More than one directive,
  or trailing non-comment content, makes it *invalid* — the parser does not take first-match-wins.
  An ambiguous manifest is a `doctor`-diagnosed fault, not a silent backend choice (dotfiles-dft.1
  experiment: a lenient parser accepted `backlog: bd` + `backlog: gh` and silently dispatched to
  `bd`).
- **Merge gate = never a marker.** The gate *is* branch protection + auto-merge settings —
  server-enforced, so the reconciler reads it live (`gh api`) at exactly the phases that need the
  remote anyway. A committed copy could only ever lie; `.repo-visibility` is the proof.
  "Attended"/"unattended" survive as *descriptions* of a repo's observed gate posture, never
  stored state.
- **Claim unifies across backends**: every claim creates the canonical `delivery/<id>` branch —
  the universal lock at the remote (first push wins); a bd-backed backlog adds the status
  transition as the online fast path. (CONTEXT.md's Claim entry updated accordingly.)

This ADR **supersedes-in-part**:

- **ADR 0004** (private-tier decision record) — its decisions stand; read its "private tier" as
  "bd-backed backlog, review-required gate".
- **ADR 0011** (public delivery claim: canonical branch is the lock) — its mechanism is *promoted*
  from public-tier-specific to the universal claim lock on both backends.

Per the frozen-generation ruling (ADR 0015), neither old ADR is reworded in place; the old bundle
generation and `.repo-visibility` keep speaking tier until retired — the two markers coexist
during cutover, each generation reading only its own.

## Consequences

- `nextdelivery` has dissolved into `clerk backlog next` + `clerk doctor`. Its remaining `bin/`
  executable is only a compatibility shim for old muscle memory; it no longer reads the retired
  marker or prints the old setup hint. Clerk owns ready-pool dispatch and `.clerk` provisioning.
- Seeds in the new generation barely mention the axes at all: dispatch is the clerk's business,
  and the gate is discovered live, so the graduated-autonomy ladder is a per-repo platform
  setting, not seed prose.
- This repo's `.clerk` says `backlog: bd` — unchanged behavior under retired vocabulary.

## History

- 2026-07-11: dotfiles committed `.clerk` with `backlog: bd`; `nextdelivery` became a
  compatibility shim over `clerk backlog next`, and its old setup hint was replaced by
  `clerk doctor`.
- 2026-07-09: the `nextdelivery` Consequences bullet was rewritten to drop the false claim
  that it was a `zsh/.zshenv` function and to state its current form instead. `nextdelivery`
  was ported from a `.zshenv` zsh function to a `bin/` executable (ADR 0001, repo-root), so it
  is reachable by pi's `/bin/bash` tool shell and yazi, not only zsh. The bullet had also
  implied the `clerk backlog next` migration was done; it isn't — `nextdelivery` still reads
  `.repo-visibility` and this repo has no `.clerk` yet. The *intended* migration target now
  reads as `bin/nextdelivery` dissolving into `clerk backlog next` + `clerk doctor`.
- 2026-07-06: strict-marker clause added (ambiguous / multi-directive `.clerk` is invalid, not
  first-match-wins). The dotfiles-dft.1 small-model experiment shipped a lenient parser that
  accepted two conflicting directives and silently picked the first; "one key" always implied a
  single directive, now stated so the contract is testable. Marker-format details otherwise
  unchanged.
