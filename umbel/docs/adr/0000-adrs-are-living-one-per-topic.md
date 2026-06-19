---
status: accepted
---

# ADRs are living, one-per-topic: edited in place, never superseded by a new ADR

This repo's ADRs are **living documents, one per decision-topic.** When a decision
evolves — even reverses — we edit that topic's ADR in place so its body always states
the *current* decision, and record the prior decision and why it changed in a short
**History** section of the same doc. We do **not** spin up a new ADR to supersede an
old one, and we do **not** leave struck-through "superseded — see ADR-N" text in the
live read path. A new ADR is created only for a genuinely **new** decision-topic.

## Context

These ADRs are read by **agents at exploration time** ("read the ADRs that touch the
area you're about to work in") on a **solo, agent-operated** repo. The orthodox ADR
model (Nygard) keeps each accepted ADR immutable and records a change by adding a *new*
ADR marked `superseded by NNNN` — an append-only log of decision snapshots. That
optimises for a *team* reconstructing history from the documents under review.

For an agent-read corpus it backfires. A superseded ADR left in `docs/adr/` is a
full-text **decoy** in the agent's primary read path: the agent may act on the stale
decision, or must chase a chain of forward pointers (today: 0001 → 0003 → 0004 → 0005)
to assemble current state. That is the same indirection ADR 0010 / dotfiles-j8x reject
elsewhere — "don't make every session chase an ADR." And the audit trail the immutable
model exists to protect is already provided two other ways, both *outside* the
decision-reading path: **git** (every edit is a commit + diff) for the raw record, and
an in-document **History** section for the curated "why we changed".

## Decision

- **One ADR per decision-topic, and it is a living document** — its body always states
  the current decision.
- **Evolutions, including reversals, are edited in place.** Update the Decision; add or
  extend a terse **History** section ("was X until <date>; changed to Y because Z"). The
  curated *why* stays in the doc so a rejected approach isn't re-proposed; the raw diff
  stays in git.
- **No supersession-by-new-ADR and no strike-through decoys.** Nothing in the live
  `docs/adr/` should require chasing a forward pointer to learn the current decision. An
  ADR may still *reference* another ADR as a related topic (context, a shared principle)
  — that is not a chase; a split current-decision is.
- **A new ADR is for a new topic, not a changed mind.** The ADR count tracks the number
  of distinct decision-topics, not how many times each was revised.
- **The number is a stable internal handle.** Because a topic's ADR is edited in place
  rather than replaced, its number is a durable reference. (Distributed artifacts still
  cite no ADR numbers at all — ADR 0010 / dotfiles-j8x; this stable handle is for
  *in-repo* reference only.)
- **`0000` is the meta-ADR** — conventions for the decision record itself; it sorts and
  reads first.

## Considered options

- **Orthodox immutable ADRs + supersession (Nygard).** Rejected here: built for team
  review/audit *from the documents*; on a solo, agent-read corpus it leaves stale decoys
  and forces pointer-chases, while git already supplies the audit trail.
- **Pure living docs, history only in git.** Rejected as the *sole* mechanism: git holds
  the raw diff but not the curated rationale. A future reader/agent needs "we tried X, it
  failed because Z" *in the doc* — hence the in-document History section.
- **Keep superseded ADRs but move them to an `adr/archive/` subdir.** Rejected: still
  fragments one topic's decision across two files; one living doc per topic is simpler and
  chase-free.

## Consequences

- **Existing ADRs are revised to conform.** ADR 0001 carries an amendment header, an
  inline strike-through, and forward pointers to 0003/0004/0005 (the old supersession
  style); 0004/0005/0007 frame themselves as "supersedes/amends ADR-N". Each topic's
  current decision is restated standalone in its owning ADR, evolution folded into a
  History section, and the decoys/forward-chases removed — without renumbering or merging
  distinct topics (legitimate inter-topic references stay).
- Future grills stop re-litigating "edit or supersede?" — the answer is always *edit the
  topic's ADR; new ADR only for a new topic.*
- `grill-with-docs` and any ADR-touching skill maintain ADRs under this model.

## History

- 2026-06-18: created. Crystallised mid-refinement (dotfiles-i8h) when the question
  "do ADRs stay frozen or evolve?" surfaced, then sharpened by the follow-up that
  supersession is itself a pointer-chase for an agent-read corpus.
