---
name: delivery-superpowers-locations
description: Inject the delivery-superpowers method's per-repo adaptations of vendored superpowers to this harness at session start — (1) the artifact-location override (specs/plans -> gitignored .local/ instead of the vendored docs/superpowers/ default) and (2) a worktree-teardown correction for finishing-a-development-branch Step 6. Leaves vendored skills untouched.
event: SessionStart
matcher: "startup|clear|compact"
command: ./inject
async: false
---

SessionStart hook for the `delivery-superpowers` method. The superpowers skills
(`writing-plans`, `brainstorming`) default to writing specs/plans into a **committed**
`docs/superpowers/{specs,plans}/` tree. Those defaults live in vendored upstream skills we
re-vendor whole, so we can't edit them — but both skills defer to "user preferences for
location", and a SessionStart `additionalContext` block IS that preference. This hook injects
it, so the override travels with the bundle and nothing is committed into the project tree.

Worktrees are deliberately NOT redirected — `finishing-a-development-branch` recognises
superpowers-owned worktrees by a hardcoded provenance list (`.worktrees/`, `worktrees/`,
`~/.config/superpowers/worktrees/`); a custom worktree dir would be created but never
auto-cleaned. Worktrees stay at `.worktrees/`.

The same hook also injects a **worktree-teardown correction**. After integration, the native
`ExitWorktree(action:"remove")` guard trips — it flags the worktree branch's commit(s) as work
that would be "discarded," because they aren't reachable from the branch's creation-time base,
even though they're safely on the integration target. The injected block tells the agent to run
one codified teardown: confirm integration with the tier oracle (private: `git merge-base
--is-ancestor HEAD main`; public: `gh pr view <PR#>` is `MERGED`; tier read from `.repo-visibility`)
and only then force-remove — loud-failing if not integrated, so the safety net stands. The hook's
purpose is "adapt vendored superpowers to this harness", spanning both blocks.

Same machinery as `delivery-base-ruleset`'s `inject`, minus the tier branch — both injected blocks
are tier-independent static text (the teardown block carries both oracles; the agent reads
`.repo-visibility` itself to pick).
