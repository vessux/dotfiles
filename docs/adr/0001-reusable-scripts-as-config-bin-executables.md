---
status: accepted
---

# Reusable repo scripts callable by non-zsh subprocesses are executables in `~/.config/bin`, not `.zshenv` functions

This repo's established convention for reusable commands is **zsh functions (or PATH
entries) in `~/.config/zsh/.zshenv`** — `md`, `nextdelivery`, and the mise shims PATH all
live there, with a comment explaining why: `.zshenv` is sourced by *every* zsh invocation
including non-interactive ones (Claude Code skills/hooks, `zsh -c`, cron), whereas `.zshrc`
is interactive-only. That convention assumes the caller is **zsh**. But some callers aren't:
yazi runs a `shell` block in a non-zsh subprocess, where a zsh function simply does not
exist — it can only invoke a real executable found on PATH. The yazi `A` → `plannotate`/`clip`
feature (`dotfiles-p4z`) is the first such caller, and it needs commands reachable from
yazi's subprocess **and** from agent shells alike.

**Decision.** Reusable scripts that must be callable from **non-zsh subprocesses** are real
executables (shebang, `chmod +x`) in a new `bin/` stow package → `~/.config/bin/`, and
`~/.config/bin` is added to PATH **in `.zshenv`** (not `.zshrc`) so fresh non-interactive zsh
callers see them too. This deliberately diverges from the `.zshenv`-function convention:
`md`/`nextdelivery` stay functions (zsh-only reach is fine for them), while any command that
needs cross-shell reach becomes an executable in `bin/`. The two conventions coexist, split by
caller type — **zsh-only reach → function in `.zshenv`; any-shell reach → executable in
`~/.config/bin`.** This record exists so the inconsistency isn't "consistency-fixed" back into a
function, which would silently break every non-zsh caller (starting with yazi).

## Considered options

- **zsh function in `.zshenv`** (the existing convention) — rejected: not callable from yazi's
  non-zsh `shell` subprocess; a function is invisible outside a zsh process.
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

- `~/.config/bin` (the `bin/` stow package) becomes the home for repo-tracked executable scripts;
  future such scripts go there rather than into `.zshenv` or a tool-specific config dir.
- First root-level `docs/adr/` entry. Umbel keeps its own context-scoped ADRs under
  `umbel/docs/adr/`; repo-wide conventions like this one live at the root.
