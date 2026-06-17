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

# md — files & URLs -> markdown, for feeding content to agents. Lives here (not
# .zshrc) so non-interactive callers see it — notably `!md` inside a Claude Code
# session, the cleanest way to drop a page/file into the chat (same reason the shims
# are here). This also makes `md` reachable by an agent's own Bash: it's not
# advertised, but `!` and agent shells are the same non-interactive zsh — there's no
# shell-level way to separate them.
#   URL  -> Jina (r.jina.ai): JS render server-side, bypasses agent-blocking, main-
#           content extraction. Auth header only if $JINA_API_KEY is set in the env
#           (keyless otherwise, ~20 req/min). NB .zsh_secrets is interactive-only, so
#           a key for non-interactive `!md` must be exported somewhere this file sees.
#   file -> markitdown (PDF/docx/pptx/xlsx; via the mise shims above).
# Stdout only — compose it: `md <url>`, `md <url> | pbcopy`, `md <url> > notes.md`.
md() {
	if [[ -z "$1" ]]; then
		print -u2 "usage: md <url|file>"
		return 2
	fi
	if [[ "$1" == http://* || "$1" == https://* ]]; then
		local auth=()
		[[ -n "$JINA_API_KEY" ]] && auth=(-H "Authorization: Bearer $JINA_API_KEY")
		curl -fsSL --max-time 120 "${auth[@]}" "https://r.jina.ai/$1"
	else
		markitdown "$1"
	fi
}
