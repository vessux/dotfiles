---
status: accepted
---

# Override vendored-skill artifact locations via a method config inject-hook

The superpowers skills `brainstorming` and `writing-plans` default to writing their specs and
plans into a **committed** `docs/superpowers/{specs,plans}/` tree. Adopting `delivery-superpowers`
on a repo therefore silently starts committing maintainer-agent scratch into that repo's history.
The defaults live in vendored upstream skills that are re-vendored whole on each superpowers
release, so they can't be edited in place — but both skills defer: *"User preferences for
plan/spec location override this default."* Nothing in the bundle carried that preference:
`delivery-base`'s `seed.<tier>.md` is method-agnostic (it must not name superpowers paths), and
`superpowers/session-start` injects only the `using-superpowers` discipline announce.

**Decision.** `delivery-superpowers` carries one method inject-hook, **for config only** —
`local/delivery-superpowers-locations`. A SessionStart `additionalContext` block declares the
per-repo "user preference" the skills defer to: specs/plans go under a gitignored,
machine-local `.local/superpowers/{specs,plans}/` root, and the agent self-heals `.gitignore`
(add + commit a `.local/` line) before the first write. No vendored skill is edited, so the
override survives re-vendor, and it travels with the bundle so every adopting repo gets it free.
Worktrees are deliberately **not** redirected (see guardrail below). The root is the generic
`.local/`, namespaced `.local/superpowers/`, to stay open for future per-repo file artifacts.

This **refines ADR-0002**: that record's "a method adds a procedure block only if needed (so
`delivery-superpowers` adds none)" was about *procedure* hooks. Superpowers still carries the
procedure; this is a distinct, second door — a *config* inject-hook — which `delivery-superpowers`
now uses for location config only.

## Considered options

- **Commit the vendored `docs/superpowers/` defaults** — rejected: that is the symptom. Every
  adopting repo would commit maintainer-agent scratch into its tree, against the design rule that
  nothing is written into the project tree but the one-line `.repo-visibility` marker.
- **Edit the vendored skills to change the default path** — rejected: superpowers is re-vendored
  whole on each release; the edit would be clobbered every upgrade.
- **Record the location in a committed `CLAUDE.md` / per-repo config** — rejected: writes into the
  project tree, drifts per-repo, and must be re-applied on every adopting repo by hand. The
  inject-hook carries it once, for all adopters, and writes nothing.
- **Put the override in `delivery-base`'s `seed.<tier>.md`** — rejected: the base seed is the
  invariant, method-agnostic contract; it must not name superpowers-specific paths. Per-repo
  *method* config has no business in the *base* contract.
- **Redirect worktrees into `.local/` too** — rejected (guardrail): `finishing-a-development-branch`
  recognises superpowers-owned worktrees by a **hardcoded** provenance list (`.worktrees/`,
  `worktrees/`, `~/.config/superpowers/worktrees/`). A custom worktree dir would be created but
  never auto-cleaned → orphaned worktrees. Worktrees stay at `.worktrees/`; `.local/` is for file
  artifacts only.
- **A superpowers-specific dir name (e.g. `.superpowers-local/`)** — rejected in favour of a
  generic `.local/` root (namespaced `.local/superpowers/`) so future per-repo machine-local
  artifacts share one gitignored root.

## Consequences

- A delivery method may carry an inject-hook for **per-repo config**, distinct from a *procedure*
  hook — closing the gap that the bundle's "Applying"/inject must own the prerequisites and
  per-repo defaults of the artifacts it introduces.
- The override travels with `delivery-superpowers` to every adopting repo and survives re-vendor;
  no vendored-skill edit, no committed scratch.
- The agent self-heals `.gitignore` for `.local/` on first artifact write.
- Bundle-body reasoning and the `## Applying` sections of `delivery-superpowers` and
  `delivery-base` are updated to state this (and `delivery-base`'s shipped tooling prerequisites:
  `plannotator` on PATH, the `tuidriver` MCP runtime).
