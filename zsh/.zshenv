# .zshenv — sourced by EVERY zsh invocation, including non-interactive ones
# (Claude Code skills/hooks, `zsh -c`, scripts, cron). .zshrc is interactive-only,
# so anything non-interactive callers must see on PATH belongs here, not there.
#
# mise shims: `mise activate` (in .zshrc) injects tool dirs via a hook that fires
# only in interactive shells, so mise-managed tools (node/just/uv/plannotator)
# were invisible to non-interactive callers — e.g. `plannotator last` from its
# skill failed with "command not found" after plannotator moved off ~/.local/bin
# onto the mise github backend. The shims dir is static and needs no activation;
# it's mise's recommended non-interactive setup (`mise doctor`). `mise activate`
# still runs later in interactive shells and prepends its own dirs, so it wins
# there — the shims are purely the non-interactive fallback.
export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
