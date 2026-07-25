---
status: accepted
---

# Project-gate adapter contract: project policy outside Clerk

## Context

Umbel ADR 0016 established that Acceptance criteria are authored during Refinement and that the
implementer does not write its own exam. Its former Project-gate amendments described the Clerk
mechanism that hands delivery to project validation. That mechanism is now a Clerk decision; Umbel
continues to own the discovery/delivery judgment loop and Acceptance-criteria craft.

Clerk must remain portable across projects. It cannot make this repository's test commands, proof
format, models, prompts, evidence retention, or independent-review policy universal. Equally, a
project must not need a daemon, artifact store, or agent merely to transform a synchronous test
command into a Clerk verdict.

## Decision

- A `.clerk` manifest references required, committed Project-gate configuration and adapter content.
  Clerk resolves both from trusted default-branch content. Missing, unreadable, malformed, or
  out-of-repository configuration fails submission closed; a delivery branch cannot supply the
  adapter that grades itself.
- A Project-gate adapter implements required `run`. Clerk sends one structured stdin Gate request
  containing Work identity/title/full Acceptance criteria, delivery branch/starting commit/worktree,
  and Submission ownership. The adapter writes exactly one Gate result JSON to stdout. Tool output,
  logs, details, evidence, and artifacts remain project policy.
- A result has `status` (`passed`, `failed`, or `pending`), `summary`, and actual
  `assessed_commit`. `pending` additionally requires an opaque `run.id`. Terminal results may carry
  an ID but do not require one. A valid failed check exits zero with `status: failed`; a broken or
  unavailable adapter/configuration, or malformed output, exits non-zero as an operational error.
- `status` is conditional: only an adapter whose `run` returned `pending` must implement it. Clerk
  retains the Claim/worktree for pending or failed results and gives the run ID back to `status` for
  reconciliation. A later submission starts a new run.
- `passed` means only that the selected Project-gate policy passed for `assessed_commit`. Clerk does
  not require or interpret individual criterion verdicts, independent verification, evidence,
  artifacts, or criterion-to-test mappings. The Work and, where present, its PR remain the
  Acceptance-criteria record.
- `submission_owner: clerk` is the minimum/default path. A passing adapter may advance the delivery
  head, but must leave its assessed commit checked out in the supplied worktree; Clerk hands off only
  that current head. `submission_owner: project-gate` is an opt-in for adapters that own changed
  refs, push/PR/CI, and lifecycle reporting.

## Consequences

- The adoption floor is a committed config and a small project-owned synchronous transform shim.
  Generic bootstrap automation is separate work; Clerk must not guess a project's validation policy.
- Projects may layer stronger verification—per-criterion ledgers, independently contextualized
  reviewers, durable evidence, or asynchronous runs—without expanding Clerk's universal contract.
- Clerk persists only its generic Gate-run metadata and relays generic results. It remains the
  workflow facade, not a validation-policy runtime.

## Related decisions

- Umbel ADR 0016 retains Acceptance-criteria and judgment-loop policy, and links here for the
  Clerk-owned Project-gate contract.
- Clerk ADR 0015 defines the opaque workflow-verb facade; Clerk ADR 0017 defines `.clerk` as its
  manifest.
