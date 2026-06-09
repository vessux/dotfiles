---
name: delivery-superpowers-locations
description: Inject the superpowers per-repo artifact-location override at session start — specs/plans go to a gitignored .local/ root instead of the vendored docs/superpowers/ default. Leaves vendored skills untouched.
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

Same machinery as `delivery-base-ruleset`'s `inject`, minus the tier branch (the override is
tier-independent).
