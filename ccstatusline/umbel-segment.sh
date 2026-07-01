#!/bin/sh
# umbel-segment.sh — ccstatusline custom-command widget: the umbel bundle
# governing THIS session, shown right after the model on line 1.
#
# Source of truth is SESSION-RESOLVED, not the .umbel-bundle pin file (the pin
# can lie: a vanilla `claude` launched in a pinned dir still reads a name).
#   name    = $UMBEL_BUNDLE, trusted only when $UMBEL_RESOLVED=1
#   version = $UMBEL_BUNDLE_VERSION, set by umbel on the bundle run path
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
# Version comes from $UMBEL_BUNDLE_VERSION, exported by `umbel run` on the
# bundle path (format "0.0.0+<hash>" — a semver placeholder until real
# versioning lands; the vanilla path drops it, matching the name's vanilla
# behaviour). We render the short hash git-style; a real semver would render
# verbatim. Was a PATH-scrape before umbel-ri9 shipped the var (dotfiles-cbt).

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

# Version from umbel's env var. Strip the "0.0.0+" semver prefix to the short
# hash for the git-style render; a real semver (no "+") passes through unchanged.
v=${UMBEL_BUNDLE_VERSION:-}
hash=${v##*+}          # "0.0.0+<hash>" -> <hash>; no-op on a real semver like 1.2.3
if [ -n "$v" ]; then
	printf '%s%s %s@%.7s%s' "$MAGENTA" "$ICON" "$name" "$hash" "$RESET"
else
	printf '%s%s %s%s' "$MAGENTA" "$ICON" "$name" "$RESET"   # best-effort: name only
fi
