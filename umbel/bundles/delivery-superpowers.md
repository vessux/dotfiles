---
name: delivery-superpowers
description: A delivery method — Jesse Vincent's superpowers discipline (plan → TDD → verify → review → finish) on top of the `delivery-base` contract. Swappable — another method can replace it while keeping the same base. Read the body to set a repo up.
extends: [delivery-base, superpowers]
hooks:
  - local/delivery-superpowers-locations
---

# delivery-superpowers

The **superpowers method** for delivery: it owns the *how* between claim and done — prep
(brainstorm if fuzzy → plan → review the plan) and execution (TDD →
verification-before-completion → code review → finish). It plugs onto `delivery-base`,
which owns the invariant lifecycle contract (scope / claim / capture-escalate / done).

`extends: [delivery-base, superpowers]`:
- **`delivery-base`** — the contract (injected) + shared tooling (`annotate`/`last`,
  `grill-with-docs`, `tuidriver`).
- **`superpowers`** — the 14-skill discipline + its own SessionStart announce-hook, which
  is what carries this method's prep + execution.

One method inject hook, for **config only** — `local/delivery-superpowers-locations`. It
redirects superpowers' file artifacts (specs/plans) to a gitignored `.local/superpowers/`
root, because the vendored skill defaults (`docs/superpowers/…`, committed) can't be edited
upstream and nothing else carries per-repo config: `delivery-base`'s seed is method-agnostic
and superpowers' own hook only announces the discipline. It carries **no procedure** —
superpowers already injects its discipline (its SessionStart announce-hook + interlinked
skills) and `delivery-base` supplies the contract, so a method *procedure* block would be
redundant. This is the "method injects its own hook if it has one" door, used here for
location config, not procedure.

## Applying

Set the tier via `.repo-visibility` per `delivery-base`. Prerequisites: `bd` (private
claim/close), `gh` (public PRs). The superpowers SessionStart hook announces the skill
set automatically.

Artifact locations are handled automatically by the `delivery-superpowers-locations` hook,
which redirects superpowers' specs/plans to a gitignored `.local/superpowers/` (the vendored
default would commit them under `docs/superpowers/`); the hook reminds the agent to ensure
`.local/` is gitignored. Worktrees stay at `.worktrees/`.

## Reasoning

- **Why superpowers is a method, not the base.** Its plan→TDD→verify→review discipline is
  one *way* to execute — swappable. The lifecycle it runs inside (scope, claim,
  capture-escalate, done) is invariant, so that lives in `delivery-base`.
- **Why extend superpowers whole (not cherry-pick).** It's a cohesive system — a
  meta-skill + announce-hook + skills that reference each other, built to be extended.
  This method uses most of it; cherry-picking would break the web. (Loose collections
  like plannotator *are* cherry-picked — see `delivery-base`'s tooling.)
