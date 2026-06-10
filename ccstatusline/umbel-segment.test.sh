#!/bin/sh
# Tests for umbel-segment.sh — the ccstatusline umbel-bundle widget.
# Run:  ./umbel-segment.test.sh   (exit 0 = all pass)
#
# Hermetic: the segment script uses only shell builtins, so PATH can be a
# synthetic value here without affecting it. We exercise all four output
# states by setting UMBEL_RESOLVED / UMBEL_BUNDLE / PATH per case via `env`.
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

# State 1: resolved + version readable, dash-in-name (the live `delivery-superpowers` shape)
out=$(env UMBEL_RESOLVED=1 UMBEL_BUNDLE=delivery-superpowers \
	PATH="/opt/umbel/bundles/delivery-superpowers-4124ef534311/bin:/usr/bin:/bin" "$SUT")
check "resolved+version, dash-in-name -> name@7hash magenta" \
	"${M}󰏗 delivery-superpowers@4124ef5${R}" "$out"

# State 2: resolved + version readable, simple name
out=$(env UMBEL_RESOLVED=1 UMBEL_BUNDLE=discovery \
	PATH="/opt/umbel/bundles/discovery-abcdef1234567/bin:/usr/bin:/bin" "$SUT")
check "resolved+version, simple name -> name@7hash magenta" \
	"${M}󰏗 discovery@abcdef1${R}" "$out"

# State 3: resolved but version unreadable — a decoy other-bundle entry must NOT match
out=$(env UMBEL_RESOLVED=1 UMBEL_BUNDLE=discovery \
	PATH="/opt/umbel/bundles/other-zzz9999/bin:/usr/bin:/bin" "$SUT")
check "resolved, no matching PATH entry -> bare name magenta" \
	"${M}󰏗 discovery${R}" "$out"

# State 4: vanilla — UMBEL_RESOLVED unset (bundle name present but ignored)
out=$(env -u UMBEL_RESOLVED UMBEL_BUNDLE=discovery PATH="/usr/bin:/bin" "$SUT")
check "vanilla (UMBEL_RESOLVED unset) -> dim grey" \
	"${G}󰏗 vanilla${R}" "$out"

# State 5: hard error — resolved but no name -> empty stdout (segment drops)
out=$(env -u UMBEL_BUNDLE UMBEL_RESOLVED=1 PATH="/usr/bin:/bin" "$SUT")
check "resolved but no name -> empty stdout" "" "$out"

echo
if [ "$fails" -eq 0 ]; then
	echo "All tests passed."
	exit 0
fi
echo "$fails test(s) failed."
exit 1
