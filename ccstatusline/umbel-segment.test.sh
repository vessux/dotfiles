#!/bin/sh
# Tests for umbel-segment.sh — the ccstatusline umbel-bundle widget.
# Run:  ./umbel-segment.test.sh   (exit 0 = all pass)
#
# Hermetic: every output state is driven purely by the umbel env vars, set per
# case via `env`. Version now comes from $UMBEL_BUNDLE_VERSION (was a PATH-scrape
# before umbel-ri9); we exercise the semver-placeholder form "0.0.0+<hash>", a
# real semver, the no-version fallback, and vanilla.
set -u

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUT="$DIR/umbel-segment.sh"

ESC=$(printf '\033')
M="${ESC}[35m"   # magenta
G="${ESC}[90m"   # dim grey
R="${ESC}[0m"    # reset

fails=0
check() {
	desc=$1; expected=$2; actual=$3
	if [ "$actual" = "$expected" ]; then
		printf 'ok   - %s\n' "$desc"
	else
		printf 'FAIL - %s\n       expected: [%s]\n       actual:   [%s]\n' \
			"$desc" "$(printf '%s' "$expected" | cat -v)" "$(printf '%s' "$actual" | cat -v)"
		fails=$((fails + 1))
	fi
}

# State 1: resolved + version (semver-placeholder form), dash-in-name
#          (the live `delivery-superpowers` shape)
out=$(env UMBEL_RESOLVED=1 UMBEL_BUNDLE=delivery-superpowers \
	UMBEL_BUNDLE_VERSION="0.0.0+4124ef534311" "$SUT")
check "resolved+version, dash-in-name -> name@7hash magenta" \
	"${M}󰏗 delivery-superpowers@4124ef5${R}" "$out"

# State 2: resolved + version (semver-placeholder form), simple name
out=$(env UMBEL_RESOLVED=1 UMBEL_BUNDLE=discovery \
	UMBEL_BUNDLE_VERSION="0.0.0+abcdef1234567" "$SUT")
check "resolved+version, simple name -> name@7hash magenta" \
	"${M}󰏗 discovery@abcdef1${R}" "$out"

# State 3: resolved + a REAL semver (no "+" prefix) -> passes through verbatim
#          (forward-compatible once real versioning lands)
out=$(env UMBEL_RESOLVED=1 UMBEL_BUNDLE=discovery \
	UMBEL_BUNDLE_VERSION="1.2.3" "$SUT")
check "resolved + real semver -> name@semver magenta" \
	"${M}󰏗 discovery@1.2.3${R}" "$out"

# State 4: resolved but version var absent -> bare name magenta (best-effort)
out=$(env -u UMBEL_BUNDLE_VERSION UMBEL_RESOLVED=1 UMBEL_BUNDLE=discovery "$SUT")
check "resolved, no version var -> bare name magenta" \
	"${M}󰏗 discovery${R}" "$out"

# State 5: not launched via umbel — UMBEL_RESOLVED unset (stale name ignored)
out=$(env -u UMBEL_RESOLVED UMBEL_BUNDLE=discovery "$SUT")
check "no umbel (UMBEL_RESOLVED unset) -> dim grey vanilla" \
	"${G}󰏗 vanilla${R}" "$out"

# State 6: explicit vanilla pick — resolved (RESOLVED=1) but no name -> dim grey
out=$(env -u UMBEL_BUNDLE UMBEL_RESOLVED=1 "$SUT")
check "vanilla pick (resolved, no name) -> dim grey vanilla" \
	"${G}󰏗 vanilla${R}" "$out"

echo
if [ "$fails" -eq 0 ]; then
	echo "All tests passed."
	exit 0
fi
echo "$fails test(s) failed."
exit 1
