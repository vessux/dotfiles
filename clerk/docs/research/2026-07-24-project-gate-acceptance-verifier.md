# Project-gate Acceptance-criteria verification research

**Question:** Must Clerk impose an independent Acceptance-criteria verifier, durable evidence, and executable-test mapping on every Project gate?

**Finding:** No. The primary sources support trusted project-controlled gate configuration, isolated validation workspaces, optional intent/evidence/reviewer loops, and head-specific results. They do not establish a universal Acceptance-criteria verification policy. Requiring one would turn Clerk's portable boundary into a policy-owning gate and make simple synchronous test adoption unnecessarily stateful.

**Decision reached in the `dotfiles-9urv.18` Refinement grill:** Clerk owns the Work's Acceptance criteria and transports them to the Project gate, but a `passed` Gate result means only that **the selected Project-gate policy passed** for the assessed commit. The project decides whether that policy includes an independent verifier, per-criterion ledger, executable-test mapping, evidence, artifacts, reviewer model, prompts, budget, or asynchronous state.

Clerk ADR 0019 records the resulting contract.

## What the sources establish

### Trusted project control plane

`no-mistakes` treats shell commands and agent selection as executable control fields: it reads them from the fetched default branch rather than the submitted branch and aborts when that trusted copy cannot be read or parsed. This supports the settled Clerk boundary: `.clerk` references a committed Project-gate configuration and adapter resolved from trusted default-branch content. The delivery branch cannot replace the adapter that validates it.

This is a control-plane rule, not a rule about the tools the adapter may invoke in the supplied delivery worktree. The Project gate owns those tools and their privileges.

### Independent review and evidence are useful optional gate capabilities

`no-mistakes` demonstrates a higher-assurance Project-gate design: disposable worktrees, an explicit user intent treated as authoritative acceptance context, separate reviewer/fixer sessions, and an evidence-oriented test step that asks for end-user-visible proof and reports insufficient evidence. Its own configuration deliberately permits a targeted deterministic test command or agent-selected targeted tests; broad regression belongs to its remote CI stage.

That is useful evidence for a project which chooses an independent verifier. It is not a reason for Clerk to require one. A project whose gate is simply `bats tests/clerk` needs only a small adapter which converts the command outcome into the generic Gate result.

### A passing result must identify what was actually assessed

GitHub's required-check behavior is commit-specific: an earlier commit's successful result does not satisfy a check for a newer head. A Project gate can legitimately advance the head while repairing or rebasing, however, so the generic rule cannot require it to assess the commit named at the start of a run.

The portable invariant is instead that a result identifies its actual `assessed_commit`. For Clerk-owned submission, Clerk may proceed only when that commit is the head it will hand off from the supplied delivery worktree. A Project-gate-owned submission reports its own changed ref and lifecycle; Clerk does not impose a Git implementation on it.

### Ephemeral runs do not require artifact persistence

A synchronous tool invocation can produce a terminal pass/fail result and disappear. No universal artifact store, durable test transcript, or run database follows from the existence of Clerk. Artifact generation, retention, and evidence URLs are Project-gate policy.

Only a Project gate which returns `pending` needs to keep enough of its own run state to answer a later `status` request. This is an implication of its chosen asynchronous behavior, not a base adoption cost. If it cannot answer, the adapter has an operational failure; Clerk does not store the gate's state for it.

## Resulting minimum contract

The minimum Project-gate adapter is a project-owned transform shim.

| Situation | Adapter requirement | Clerk behavior |
| --- | --- | --- |
| Synchronous project check | Required `run` reads one Gate request and writes one terminal result JSON to stdout. | Records/relays the result and, with Clerk-owned submission, hands off only the assessed current worktree head. |
| A check reports failure | Exit `0` with `status: "failed"`. | Retains Claim/worktree for delivery to repair or rerun. |
| Adapter/configuration cannot execute, or output is malformed | Non-zero exit. | Reports an operational error, distinct from an honest failed verdict. |
| Asynchronous gate | `run` may return `pending` and must include `run.id`; it then implements `status`. | Retains Claim/worktree and reconciles that run through `status`. |

Every result has `status`, `summary`, and `assessed_commit`. A `run.id` is required only for `pending`; terminal runs may supply one for their own purposes. The adapter controls details and logs: stdout is exactly one result JSON, while raw tool output can be captured, discarded, sent to stderr, or included as project-selected details. Clerk does not parse it.

A project can layer a stricter verifier on this contract. For example, it may require an independently gathered verdict for every criterion; executable criteria may require committed focused tests, while UI/CLI behavior may require end-to-end evidence. Those are valuable Project-gate policies, but are not Clerk fields or baseline requirements.

## Adoption consequence

Project-gate configuration remains required and missing configuration fails submission closed: Clerk must not silently invent validation policy. The adoption floor is nevertheless only committed configuration plus a small adapter. Generic Adoption/bootstrap automation is intentionally separate work, filed as Clerk capture `dotfiles-1vfp`, because a generic tool cannot choose a project's test commands or evidence policy without violating this boundary.

## Primary sources

1. [Clerk ADR 0019, “Project-gate adapter contract: project policy outside Clerk”](../adr/0019-project-gate-adapter-contract.md). Records the Project-gate boundary resulting from this research; Umbel ADR 0016 separately owns Acceptance-criteria craft and the judgment loop.
2. [`kunchenguid/no-mistakes` gate model at commit `88dc204f933bbccee5fd144f2fa1e74cb52704c2`](https://github.com/kunchenguid/no-mistakes/blob/88dc204f933bbccee5fd144f2fa1e74cb52704c2/docs/src/content/docs/concepts/gate-model.md). Documents disposable worktrees, a fixed validation pipeline, asynchronous daemon state, and the distinction between pipeline mechanics and project configuration.
3. [`no-mistakes` repository configuration reference at the same commit](https://github.com/kunchenguid/no-mistakes/blob/88dc204f933bbccee5fd144f2fa1e74cb52704c2/docs/src/content/docs/reference/repo-config.md). Establishes default-branch loading for executable control fields and describes targeted test commands and optional evidence storage.
4. [`no-mistakes` agent guide at the same commit](https://github.com/kunchenguid/no-mistakes/blob/88dc204f933bbccee5fd144f2fa1e74cb52704c2/docs/src/content/docs/guides/agents.md). Documents separate reviewer/fixer sessions, explicit intent as acceptance context, evidence-oriented tests, and a non-degrading gate when its chosen agent is unavailable.
5. [`no-mistakes` test-step source at the same commit](https://github.com/kunchenguid/no-mistakes/blob/88dc204f933bbccee5fd144f2fa1e74cb52704c2/internal/pipeline/steps/test.go). Shows its project-selected evidence policy: focused tests, end-user evidence where possible, and an honest warning when proof is unavailable.
6. [GitHub Docs: Troubleshooting required status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks). Establishes commit-specific required check behavior.
7. [GitHub Docs: Secure use of `pull_request_target`](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target). Warns against checking out and executing untrusted pull-request code in a privileged context.
