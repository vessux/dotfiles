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

- `zsh/.zshenv`'s `nextdelivery` (which dispatches on `.repo-visibility` and hints at the
  nonexistent `umbel adopt`) dissolves into `clerk backlog next` + `clerk doctor`; `clerk doctor`
  owns marker provisioning.
- Seeds in the new generation barely mention the axes at all: dispatch is the clerk's business,
  and the gate is discovered live, so the graduated-autonomy ladder is a per-repo platform
  setting, not seed prose.
- This repo's `.clerk` says `backlog: bd` — unchanged behavior under retired vocabulary.
