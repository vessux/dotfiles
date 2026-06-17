#!/bin/sh
# umbel-segment.sh — ccstatusline custom-command widget: the umbel bundle
# governing THIS session, shown right after the model on line 1.
#
# Source of truth is SESSION-RESOLVED, not the .umbel-bundle pin file (the pin
# can lie: a vanilla `claude` launched in a pinned dir still reads a name).
#   name    = $UMBEL_BUNDLE, trusted only when $UMBEL_RESOLVED=1
#   version = STOPGAP, scraped from PATH (see below)
#
# A real bundle requires BOTH vars: `umbel run` spawns claude with
# UMBEL_RESOLVED=1 on EVERY launch (it's the shim's re-entrancy guard), and
# sets UMBEL_BUNDLE only when a bundle actually resolved — its vanilla path
# (execVanilla) keeps RESOLVED=1 but drops the name. So a missing/empty name
# under RESOLVED=1 means "vanilla", never an error.
#
# Output states (raw 16-color SGR; wired with preserveColors:true so this
# script owns color, and colorLevel:1/ansi16 keeps it theme-driven):
#   resolved + version   -> magenta  "󰏗 name@<7hash>"
#   resolved, no version -> magenta  "󰏗 name"          (version best-effort)
#   vanilla / no bundle  -> dim grey "󰏗 vanilla"
# "vanilla" covers an explicit vanilla pick (RESOLVED=1, no name) AND a claude
# not launched via umbel at all (RESOLVED unset) — both mean no bundle governs.
#
# VERSION SOURCE IS FRAGILE — graduates via dotfiles-cbt / umbel-ri9:
# Claude appends each --plugin-dir's bin/ to PATH (umbel src/bundle/
# claude-args.ts), so the session-resolved bundle dir
# ".../umbel/bundles/<name>-<hash>/bin" lands in PATH. We scrape <hash> there
# and truncate to 7 (git-style). This leans on Claude's plugin->PATH behaviour,
# NOT an umbel contract, so version is best-effort and NAME always comes from
# the solid $UMBEL_BUNDLE env. dotfiles-cbt replaces this scrape with a
# umbel-provided env var once umbel-ri9 ships it.

ICON='󰏗'
ESC=$(printf '\033')
MAGENTA="${ESC}[35m"
GREY="${ESC}[90m"
RESET="${ESC}[0m"

# Vanilla / no bundle: either claude wasn't launched via umbel (RESOLVED unset)
# or umbel's vanilla path resolved with no name. Both -> dim grey "󰏗 vanilla".
name=${UMBEL_BUNDLE:-}
if [ "${UMBEL_RESOLVED:-}" != 1 ] || [ -z "$name" ]; then
	printf '%s%s vanilla%s' "$GREY" "$ICON" "$RESET"
	exit 0
fi

# Best-effort version: find THIS bundle's PATH entry and read its hash.
hash=
oldifs=$IFS
IFS=:
for entry in $PATH; do
	case $entry in
	*/umbel/bundles/"$name"-*/bin)
		base=${entry%/bin}     # .../umbel/bundles/<name>-<hash>
		base=${base##*/}       # <name>-<hash>
		hash=${base#"$name"-}  # <hash>  (literal "name-" prefix stripped)
		break
		;;
	esac
done
IFS=$oldifs

if [ -n "$hash" ]; then
	printf '%s%s %s@%.7s%s' "$MAGENTA" "$ICON" "$name" "$hash" "$RESET"
else
	printf '%s%s %s%s' "$MAGENTA" "$ICON" "$name" "$RESET"
fi
