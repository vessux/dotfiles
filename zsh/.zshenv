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

# ~/.config/bin — repo-tracked executable scripts (the `bin/` stow package). On PATH here,
# not .zshrc, so non-interactive callers see them (same reason as the shims above). And these
# are real executables, not .zshenv functions like `md`/`nextdelivery` below, so NON-zsh
# subprocesses can call them too — notably yazi's `shell` block (the `A` key runs `plannotate`,
# which pipes to `clip`). See docs/adr/0001-reusable-scripts-as-config-bin-executables.md.
export PATH="$HOME/.config/bin:$PATH"

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

# nextdelivery — list THIS repo's "ready for delivery" backlog, dispatching on the repo's
# delivery tier so neither you nor an agent hand-reconstructs the per-tier query. Zero-arg,
# read-only LISTER: it runs the native backlog tool and passes the output through verbatim
# (native colours/columns/paging) — no arg passthrough, no reformatting, no tier header.
# Lives here (not .zshrc) so non-interactive callers — notably an agent's own Bash — see it,
# same reason as `md` above.
#
# Tier comes from the committed repo-root `.repo-visibility` marker (public|private), read
# exactly as the umbel ruleset-inject hooks read it. It NEVER defaults a tier.
#   private -> `bd ready --label stage:ready`. bd ready already excludes
#              in_progress/blocked/deferred, and `bd update --claim` is the atomic pickup,
#              so listing the refined-ready set is concurrency-safe.
#   public  -> `gh issue list --label ready-for-agent`. Per ADR 0011 the claim
#              relabels off ready-for-agent (the canonical work-branch is the lock),
#              so the simple label query lists only unclaimed work — no no:assignee filter.
#   missing/unreadable/unknown marker, or not in a git repo -> stderr error + fix hint,
#              exits non-zero.
nextdelivery() {
	local repo_root marker tier
	local hint="  set the tier: create a one-line .repo-visibility at the repo root containing 'public' or 'private' and commit it (see 'umbel adopt')."
	repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
	if [[ -z "$repo_root" ]]; then
		print -u2 "nextdelivery: not in a git repo — no .repo-visibility tier marker to read"
		print -u2 "$hint"
		return 1
	fi
	marker="$repo_root/.repo-visibility"
	if [[ ! -r "$marker" ]]; then
		print -u2 "nextdelivery: no readable .repo-visibility tier marker at $marker"
		print -u2 "$hint"
		return 1
	fi
	tier="$(tr -d '[:space:]' < "$marker" 2>/dev/null)"
	case "$tier" in
		private)
			# bd list --ready (NOT bd ready): identical ready-set membership, but bd ready's
			# empty-result line falsely reads "all issues have blocking dependencies" when the
			# stage:ready filter simply matched nothing. bd list says a neutral "No issues found." (q1p)
			bd list --ready --label stage:ready --sort priority
			;;
		public)
			gh issue list --label ready-for-agent
			;;
		*)
			print -u2 "nextdelivery: unrecognised tier '${tier}' in .repo-visibility (want 'public' or 'private')"
			print -u2 "$hint"
			return 1
			;;
	esac
}
