---
status: accepted
---

# Discovery/delivery backlog workflow: beads inbox, tier-split backlog, ADRs as the decision record

We adopt a two-track workflow across projects — **discovery** (capture → refine)
and **delivery** (build → ship) — shipped as two umbel bundles whose `bundle.md` carries
the setup playbook. **beads** is the always-open capture inbox on every project
(`bd create`, synced over the repo's own git origin); what an inbox item graduates *into*
depends on whether the project has an audience to curate for. On **public** projects the
real backlog is **GitHub Issues** — a refined bead is fleshed into an issue and the bead
is then *closed* (one-way, no bidirectional sync). On **private** projects **beads itself
is the backlog** (`bd ready` + dependencies). Decisions are recorded as **ADRs** (+ a
`CONTEXT.md` glossary) on **both** tiers (the decision-record mechanism is ADR 0004's
topic). This replaces the prior local-only `backlog.jsonl` + `worklog.jsonl` convention
("borklog").

Organising principle: **public = reinforceable industry standards** (GitHub Issues +
ADRs + Pocock skills); **private = beads-as-backlog** with the *same* ADR + `CONTEXT.md`
decision record (ADR 0004). beads
is the common capture substrate; the harness owns the in-session now-layer and auto-memory
owns agent recall — neither moves into beads.

## Considered options

- **beads as the public backlog / agent execution surface** — rejected: beads is a private
  tool nobody else runs. A public backlog must be reinforceable — file-able and
  PR-referenceable by external contributors — which is GitHub Issues. beads stays the inbox.
- **Pure-Yegge (beads = the "now" layer, distant backlog elsewhere)** — rejected: the
  disposable now-layer is already the harness's job (its task list); duplicating it in
  beads adds nothing.
- **Bidirectional bd↔GitHub sync** — rejected: beads' GitHub sync is less mature than its
  GitLab sync, and *closing the bead on promotion* removes any need for a live link. Flow
  is one-way beads → GitHub.
- **Worklog kept private on public repos** — rejected: a private file in a *public* repo
  can't also be git-synced across machines without a separate channel, and the worklog is
  non-sensitive technical rationale anyway. A private idiom is also silently skipped on a
  contributor's PR, whereas ADRs are enforceable. So public uses ADRs; the worklog
  survives only on private repos, where committing it is private *and* synced for free.
- **beads `remember` as the decision record / a single global cross-project inbox** —
  rejected: `remember` overlaps auto-memory (kept authoritative), and a global inbox
  conflicts with beads' per-repo git-origin sync and the `bd github` one-repo-per-workspace
  model. Capture is per-repo.
- **A setup skill / scripted migration** — rejected: the deliverable is the two bundles'
  `bundle.md`, describing the *target state and reasoning* so the applying agent computes
  the migration per repo. No script can cover every starting point.

## Consequences

- On public projects beads runs at ~10% of its capability (capture + refine); its
  dependency engine is a planning aid, not the work driver. Accepted — it cleanly replaces
  `backlog.jsonl` and adds cross-machine sync.
- **openlock is not greenfield**: it currently runs beads as a *stealth working backlog*
  (the private-tier shape) while being a public project. Adopting this is a reshape
  (stealth → committed inbox + GitHub backlog), handled per-repo, not a fresh `bd init`.
- The "basically online" sync (git-origin-as-Dolt-remote + auto-commit + auto-push +
  git hooks) is mechanism-confirmed but its exact knobs need a hands-on check on first setup.

## History

- Originally specified three things now owned by their own ADRs: the discovery phase model was
  "capture → triage → prep", renamed to **capture → refine** (ADR 0003); the private tier recorded
  decisions in a committed `worklog.jsonl`, dropped in favour of ADRs + `CONTEXT.md` (ADR 0004); and
  the capture verb was `bd q`, changed to `bd create` (ADR 0005). The body above states the current
  workflow; each of those ADRs owns the rationale for its change.
