# Project-gate configuration

`clerk backlog submit <id>` is validated by a required Project gate. Clerk reads the
configuration and adapter from the trusted default branch, never from the delivery
branch.

`.clerk` keeps the normal backend binding and names a repository-relative JSON config:

```text
backlog: bd
project-gate: clerk/project-gate.json
```

The config names a repository-relative executable adapter and its handoff owner:

```json
{"adapter":"clerk/project-gate","submission_owner":"clerk"}
```

`submission_owner` defaults to `clerk`; `project-gate` is the explicit opt-in.
Both paths must stay inside the repository. Missing, unreadable, or malformed trusted
content stops submission as an operational error.

## Adapter protocol

Clerk runs the trusted adapter as `adapter run`, writing one JSON request to stdin:

```json
{
  "work":{"id":"dotfiles-abc","title":"…","acceptance_criteria":"…"},
  "delivery":{"branch":"delivery/abc","starting_commit":"<sha>","worktree":"<path>"},
  "submission_owner":"clerk"
}
```

The adapter writes exactly one JSON Gate result to stdout. Every result has `status`
(`passed`, `failed`, or `pending`), `summary`, and `assessed_commit`. A `pending`
result additionally has `run.id`. Failed checks are a valid zero-exit `failed` result;
non-zero execution and malformed output are operational errors.

Pending metadata is retained with the Claim. `clerk backlog gate <id>` invokes
`adapter status` only for that pending run, supplying the saved request plus
`{"run":{"id":"…"}}`; another `submit` always begins a fresh `run`.

For Clerk-owned handoff, a passing `assessed_commit` must be the current supplied
worktree head before Clerk pushes and opens the PR. A Project-gate-owned passed result
must include `{"delivery":{"status":"completed"}}`; Clerk then records the Work
closed and does not create refs or PRs.

The adapter owns all project-specific validation, logs, evidence, artifact, and
independent-review policy. Dotfiles' `clerk/project-gate` is the intentionally small
synchronous transform of `bats tests/clerk` and `shellcheck -S error bin/*`.
