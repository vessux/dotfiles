---
status: accepted
---

# Reusable repo scripts are executables in `~/.config/bin`, not `.zshenv` functions

Reusable commands in this repo used to live as **zsh functions (or PATH entries) in
`~/.config/zsh/.zshenv`** — `md`, `nextdelivery`, and the mise shims PATH all lived there,
with a comment explaining why: `.zshenv` is sourced by *every* zsh invocation including
non-interactive ones (Claude Code skills/hooks, `zsh -c`, cron), whereas `.zshrc` is
interactive-only. That convention assumed the caller is **zsh**. But several callers aren't:
yazi runs a `shell` block in a non-zsh subprocess where a zsh function simply *does not
exist* — it can only invoke a real executable on PATH — and **pi's `bash` tool runs as
non-interactive `/bin/bash`**, which neither sources `.zshenv` nor speaks zsh function
syntax, so a `.zshenv` function is invisible to the agent's own shell (this is what surfaced
the breakage that collapsed the coexistence; see History). The yazi `A` →
`plannotate`/`clip` feature (`dotfiles-p4z`) was the first such caller; agent Bash joined as
a co-equal one.

**Decision.** Reusable repo scripts callable from **any caller** are real executables
(shebang, `chmod +x`) in a `bin/` stow package → `~/.config/bin/`, and `~/.config/bin` is
added to PATH **in `.zshenv`** (not `.zshrc`) so fresh non-interactive zsh callers see them
too. The defining caller was yazi's `shell` block, which runs a non-zsh subprocess where a
zsh function simply does not exist — it can only invoke a real executable on PATH. Agent
shells are now the same kind of caller: **pi's tool shell is `/bin/bash` (not zsh)**, so it
neither sources `.zshenv` nor speaks zsh function syntax — any script that must be reachable
as a bare command from an agent's Bash, a yazi `shell` block, `!`-commands, hooks, or cron is
an executable in `bin`. **No repo script stays a zsh function in `.zshenv`:** `md` and
`nextdelivery` were ported from `.zshenv` functions to `bin/` executables once the
agent-shell-not-zsh reality was confirmed (they had been the holdout exception); see
History. This record exists so a future "consistency" move back toward `.zshenv` functions is
rejected up front — it would silently break every non-zsh caller (yazi, pi's bash, cron).

## Considered options

- **zsh function in `.zshenv`** (the prior convention) — rejected: not callable from yazi's
  non-zsh `shell` subprocess nor from pi's `/bin/bash` tool shell; a function is invisible
  outside the zsh process that sourced it. Held for `md`/`nextdelivery` under the assumption
  agent shells were non-interactive zsh; that assumption broke when pi pinned `/bin/bash`,
  and they were moved to `bin/` (History).
- **Script inside the `yazi/` package, called by absolute path** — rejected: kills reuse (not a
  bare command on PATH) and would be duplicated the moment a second caller wants it. `clip` is
  generic (`md <url> | clip`); it shouldn't be buried in one tool's config.
- **PATH entry in `.zshrc`** — rejected: interactive-only. yazi would still work (it inherits PATH
  from the interactive shell that launched it), but a fresh non-interactive `zsh -c` from Claude
  Code / hooks / cron would not — the exact "command not found" lesson already recorded in
  `.zshenv` when plannotator moved off `~/.local/bin`.
- **Separate `stow --target ~/.local/bin`** — rejected: breaks the single `stow .` flow
  (`.stowrc` targets `~/.config`), and `~/.local/bin` is for installed binaries
  (`plannotator`, `openlock`), not repo-tracked scripts.

## Consequences

- `~/.config/bin` (the `bin/` stow package) is the home for **all** repo-tracked executable
  scripts; `bin/` is the single convention, not the split-by-caller-type coexistence with
  `.zshenv` functions this ADR first recorded (that coexistence collapsed once agents' Bash
  shells joined yazi as non-zsh callers — see History).
- First root-level `docs/adr/` entry. Umbel keeps its own context-scoped ADRs under
  `umbel/docs/adr/`; repo-wide conventions like this one live at the root.

## History

- 2026-07-09: `md` and `nextdelivery` ported from `.zshenv` zsh functions to `bin/`
  executables, collapsing the split-by-caller-type coexistence this ADR first recorded into
  one convention (executable in `bin/`). The holdout collapsed because pi (this repo's agent
  harness) runs its `bash` tool as non-interactive `/bin/bash`, not zsh — it never sourced
  `.zshenv`/`.zshrc`, so `md` and `nextdelivery` returned "command not found" inside the
  agent while still working in the user's interactive zsh. A zsh function is invisible to
  `/bin/bash`; an executable on PATH (already ensured by the `.zshenv` PATH add) is
  shell-agnostic. The same reach applies to any future agent-harness shell choice that
  diverges from zsh. The retry snippet the inline function comment had carried was dropped —
  `bd list --ready --label stage:ready --sort priority` now lives verbatim in
  `bin/nextdelivery`.
- 2026-07-11: `nextdelivery` retired to a compatibility shim that execs `phyllary backlog next`.
  `md` remains the exemplar reusable helper in `bin/`; Phyllary owns ready-pool dispatch and setup
  diagnosis now.
