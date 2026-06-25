---
status: accepted
---

# Public-tier delivery claim: the canonical work-branch is the lock (ref-creation CAS)

Public delivery claims a unit by atomically **creating the canonical issue branch
`delivery/<N>`** — git ref creation is a compare-and-swap, so the first agent wins and any
later create fails — rather than by assigning the issue. The work-branch *is* the lock; the
`ready-for-agent` relabel is kept only as list-hygiene, not for correctness.

## Context

Public repos use GitHub Issues as the backlog (ADR 0004). The delivery contract
(`seed.public.md`) claimed a unit by "assign the issue to yourself and signal in-progress".
That gives **no atomic mutual exclusion** once the concurrent workers are *agents sharing one
GitHub identity*: assignment is not a compare-and-swap, and `@me` / `no:assignee` carries no
"which agent holds it" signal because every agent is the same user. Two agents both pick the
same `ready-for-agent` issue → double work; an assignee-based "hide claimed work" filter can't
tell held from free.

Private has no such problem: `bd update --claim` is an **atomic state transition** (→
`in_progress`), and `bd ready` excludes `in_progress` regardless of assignee — so same-user
agents are serialized by the beads transition, not by identity. The asymmetry surfaced while
refining the `nextdelivery` lister (dotfiles-t24 → dotfiles-ie4): the public tier appeared to
lack any atomic claim primitive.

## Decision

The premise "GitHub has no atomic claim primitive" is **false**. Git ref creation *is* a
compare-and-swap: the server accepts the first creation of a ref and rejects any later create
of the same ref (REST `POST …/git/refs` → `422 Reference already exists`; a `git push` of an
existing ref is rejected). It is atomic and **identity-independent** — exactly what assignment
lacks.

So, public-tier claim:

- **Claim = create the canonical branch `delivery/<N>` server-side** with a raw ref create
  (`gh api -X POST …/git/refs`, branched from the default branch). Ref creation is the CAS: the
  first agent wins; any later create of the same ref fails (`422 Reference already exists`) → that
  loser picks another issue. **Not** `gh issue develop` — the build-time check (Consequences) found
  it *adopts* a pre-existing linked branch rather than failing, so it is not a CAS.
- **The work-branch is the lock.** The delivery method isolates *onto* `delivery/<N>`
  (`.worktrees/<N>` tracking it) rather than inventing a name. Isolation is already mandatory in
  the contract, so fixing the branch name is a thin constraint, not a new step — and the single
  issue-named branch is self-documenting.
- **Relabel is list-hygiene, not the lock.** On winning, relabel the issue off `ready-for-agent`
  (→ `in-progress`) so `nextdelivery`'s public query stays the simple
  `gh issue list --label ready-for-agent` (dotfiles-6i5). Because the *branch* is the lock, a
  relabel race is harmless (both attempts converge to the same label state).
- **Release = the inverse of claim:** delete `delivery/<N>` + re-add `ready-for-agent` (drop
  `in-progress`). This keeps the lock reversible — no roach motel.

## Considered options

- **Assignment as the claim** (the prior contract) — rejected: not a CAS; `@me` is identical
  across same-user agents, so neither the claim nor a `no:assignee` filter distinguishes held
  from free.
- **Relabel-off-`ready-for-agent` as the lock** — rejected *as the lock* (kept only as
  list-hygiene): label edits are idempotent/last-write-wins with no per-agent token, so two
  agents both "succeed" and both proceed. It prunes the list for the *next* agent but does not
  serialize the two racing on the same issue.
- **Optimistic claim-comment with a deterministic tiebreak** (each agent posts an identifiable
  claim comment; earliest by `created_at`/node-id wins; losers release) — rejected: it works and
  is identity-independent, but adds a polling protocol, a settle window, and extra API calls for
  no benefit over a true lock.
- **Distinct GitHub identities per agent** (bot accounts / per-agent PATs) — rejected: it makes
  assignment a real signal again, but at the cost of provisioning and managing N identities —
  operational overhead deliberately avoided.

## Consequences

- `seed.public.md`'s claim step changes from "assign yourself" to: create `delivery/<N>` (CAS) →
  on win, relabel + worktree onto it; release = delete branch + re-add label. The done step is
  unchanged in spirit (PR `Closes #N`; merging auto-closes).
- The public delivery method must isolate **on** the canonical branch — a thin constraint on the
  otherwise-method's-call branch naming (`delivery-base` already mandates *that* you isolate).
- `nextdelivery`'s public path (dotfiles-6i5) resolves to `gh issue list --label ready-for-agent`,
  still gated on this landing (the relabel is what makes that query exclude claimed work).
- **Build-time check (resolved):** `gh issue develop` does **not** fail on an existing branch — it
  *adopts* it, printing "Using existing linked branch" and exiting 0 (confirmed against gh 2.93.0:
  it runs `ListLinkedBranches` + `findExistingLinkedBranchName` and only calls the
  `createLinkedBranch` mutation when no match exists). So the claim uses the raw `git/refs` create
  instead — live-verified: re-POST of an existing ref returns `422 Reference already exists`.
  Trade-off accepted: the branch is a plain ref, not issue-*linked*, but its `delivery/<N>` name
  is still self-documenting.
- **Not solved here:** abandoned claims (a dead agent leaves an orphan `delivery/<N>`, locking the
  issue out of the lister). Only *manual* release is specified. Automatic, cross-tier stale-claim
  reclaim — which private's stuck `in_progress` beads need too — is a separate bead.
- Private tier is unchanged.
