# Workspace isolation is a base delivery invariant

The delivery contract (`delivery-base`) requires every unit to be built in a working directory that is exclusively the agent's own — never the shared/default checkout — before any code is touched. Stated as a *property* in both tier seeds; *how* a method achieves it (superpowers uses `using-git-worktrees` → `.worktrees/`) stays the method's call.

## Context

`delivery-base.md` deliberately delegates "branching strategy, prep, execution" to the method, so an isolation rule looks like it belongs in a method (`delivery-superpowers`), not the base. An incident (umbel gh#18 / PR#21, 2026-06-10) exposed the gap: with the working tree already dirty with unrelated in-flight edits, the agent ran `git checkout -b` in place and had to hand-stage four files to keep the unrelated changes out of the commit. Nothing in the contract made isolation the default.

## Decision

Isolation is a **safety invariant** (*that* you isolate), distinct from **branching strategy** (*how*) — so it belongs in the base, applying to every present and future delivery method. A dedicated branch alone does not satisfy it: branch state is global to a checkout, so building in place corrupts any other session in that folder and rules out running delivery agents concurrently. The true property is therefore an **exclusive working directory**, not just a branch. The base states the property; the mechanism stays the method's.

## Considered Options

- **Put it in the method (`delivery-superpowers`).** Rejected: would be re-litigated per method, and forces a procedure block into a method that deliberately ships none. The invariant must hold regardless of which method runs.
- **Mandate a worktree in the base.** Rejected: imports mechanism into the base, over-constraining future methods that might isolate via a fresh clone, container, or remote box.

## Consequences

- No size-based gradient: isolation is flat-required, so "small/mechanical change → skip" is not a sanctioned escape hatch.
- No edit to vendored superpowers skills (per ADR 0006): the injected base invariant counts as the "declared worktree preference" that flips `using-git-worktrees` from ask-consent to just-do-it, and a worktree's clean checkout removes any need to stash/hand-stage unrelated work.
