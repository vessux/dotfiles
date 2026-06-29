---
status: accepted
---

# Worktree teardown: keep the native path, gate the force-remove on a tier-appropriate "merged?" oracle

The canonical delivery finish builds in a superpowers worktree, integrates, then tears the worktree
down with `ExitWorktree(action:"remove")`. That native remove-guard trips on **every** integrated
delivery, on both tiers: it refuses because the worktree branch holds commit(s) that aren't
reachable from the branch's *creation-time base*, and reports them as work that would be
"discarded" — even though they are safely on the integration target. Decision: stay on the native
path, and codify a single first-try teardown that confirms integration with a **tier-appropriate
oracle**, then force-removes — loud-failing if the work is not actually integrated.

## Context

`ExitWorktree(action:"remove")` guards against losing un-integrated work: it refuses when the
worktree branch has commits not on its original (creation-time) base unless `discard_changes:true`.
After our integration step the branch's commit(s) are no longer reachable from that frozen base, so
the guard trips on the normal, correct flow. True on both tiers:

- **private** — ff-merge into local `main`: the commit is on `main` but still ahead of the frozen base.
- **public** — PR squash/rebase merge: `main` gets a *new* commit; the branch's commits are
  genuinely not ancestors of `origin/main`.

This is recurring friction on the happy path of every delivery ("we run into it all the time"). The
manual workaround had been: prove safety with `git merge-base --is-ancestor`, then pass
`discard_changes:true` by hand each time — which both adds a dance and *trains* the reflex to pass
`discard_changes:true`, the very flag that would lose work if the merge had **not** happened.

The fix rests only on the git invariant that **deleting a branch ref never loses a commit reachable
from the integration target** — not on any guard internals (deliberately not reverse-engineered).

## Decision

Stay on the native `EnterWorktree`/`ExitWorktree` path. Codify one first-try teardown: confirm
integration via the tier oracle, then go straight to the force-remove. Loud-fail if the oracle says
"not integrated" — that preserves the safety net and kills the reflexive-`discard_changes` hazard.

- **private** (in-session, at finish — push is deferred to the user, so `origin/main` lags):

  ```
  git merge-base --is-ancestor HEAD main        # LOCAL main; run from inside the worktree
  -> ExitWorktree(action:"remove", discard_changes:true)
  ```

- **public** (deferred until *after* the PR lands; the worktree is kept alive through review per
  `finishing-a-development-branch` Option 2):

  ```
  [ "$(gh pr view <PR#> --json state -q .state)" = "MERGED" ]   # squash/rebase-proof
  -> ExitWorktree(action:"remove", discard_changes:true)
  ```

**Why the oracles differ.** A squash/rebase merge destroys commit identity, so an ancestry check is
invalid on the public path — ask the integration source of truth (`gh`) instead. Note the public
work is safe the moment it is **pushed** (the remote PR branch holds it); the `MERGED` check is a
"don't tear down until it lands" *procedural* gate, not the data-loss guard.

**Where it lives.** The correction is injected by the method's `delivery-superpowers-locations` hook
(tier read from `.repo-visibility`, as everywhere). It targets `finishing-a-development-branch` Step 6
— a vendored superpowers skill we can't edit — and is specific to the superpowers worktree flow, so
it rides with the method that owns that flow rather than the method-agnostic `delivery-base` contract
or the vendored skill itself. That hook is the delivery-superpowers method's single "adapt vendored
superpowers to this harness" inject; it carries both the artifact-location override and this teardown
correction (the hook's `HOOK.md` and the bundle manifest state the two-block purpose).

## Rejected (do not revisit)

- **Switch to `.worktrees/` + plain-git teardown.** `using-git-worktrees` calls this the
  "#1 mistake / fighting the harness." Out.
- **Ancestry-gated teardown as a universal rule.** Invalid under public squash — `is-ancestor` is
  false after a squash merge.
- **Upstream feature-request to the harness guard.** Only helps the ff case; the harness
  fundamentally can't know about an external squash-merge, so our oracles are strictly
  better-positioned. No follow-up captured.
- **A `~/.config/bin` helper.** Teardown is `oracle && <tool call>`; a tool call can't be wrapped in
  a shell command. It is a 2-line procedure, not a script (the reusable-scripts-as-`~/.config/bin`
  rule does not reach it).

## Consequences

- `discard_changes:true` on every teardown is intentional and safe **because it is gated** by a
  same-line "is it integrated?" oracle — it reads dangerous out of context, which is why it earns
  this record.
- The reflex hazard is removed by construction: the force-remove is reachable only past a passing
  oracle; a failing oracle stops loudly.
- The two-oracle split is load-bearing — copying the private `is-ancestor` check onto the public
  path would pass or fail wrongly under squash.
