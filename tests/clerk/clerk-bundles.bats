#!/usr/bin/env bats
# clerk-bundles.bats — clerk-native bundle generation (dotfiles-dft.7)

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	NEW_ARTIFACTS=(
		"umbel/bundles/clerk-discovery.md"
		"umbel/bundles/clerk-delivery-base.md"
		"umbel/bundles/clerk-delivery-superpowers.md"
		"umbel/hooks/local/clerk-session-start"
		"umbel/skills/local/clerk-presort"
	)
	FROZEN_PATHS=(
		"umbel/bundles/discovery.md"
		"umbel/bundles/delivery-base.md"
		"umbel/bundles/delivery-superpowers.md"
		"umbel/hooks/local/discovery-ruleset"
		"umbel/hooks/local/delivery-base-ruleset"
		"umbel/hooks/local/delivery-superpowers-locations"
		"umbel/skills/local/presort"
	)
	OPACITY_TOKEN_RE='(^|[^[:alnum:]_])(bd|beads?|tier|repo-visibility)([^[:alnum:]_]|$)'
}

@test "clerk-native artifacts keep Clerk opaque" {
	cd "$REPO_ROOT"
	# Literal acceptance probe: the refined source artifacts carry none of the retired/backend words.
	run grep -RinE 'bd|beads|tier|repo-visibility' "${NEW_ARTIFACTS[@]}"
	[ "$status" -eq 1 ]
	[ "$output" = "" ]

	# Token probe with controls: do not make ordinary substrings like TBD or subdirectories red.
	printf 'TBD subdirectories data-path 4Bny\n' >"$BATS_TEST_TMPDIR/opacity-negative.txt"
	printf 'use bd-create here\n' >"$BATS_TEST_TMPDIR/opacity-positive.txt"
	run grep -inE "$OPACITY_TOKEN_RE" "$BATS_TEST_TMPDIR/opacity-negative.txt"
	[ "$status" -eq 1 ]
	run grep -inE "$OPACITY_TOKEN_RE" "$BATS_TEST_TMPDIR/opacity-positive.txt"
	[ "$status" -eq 0 ]

	run grep -RinE "$OPACITY_TOKEN_RE" "${NEW_ARTIFACTS[@]}"
	[ "$status" -eq 1 ]
	[ "$output" = "" ]
}

@test "old generation paths are untouched in the worktree" {
	cd "$REPO_ROOT"
	run git diff --name-only -- "${FROZEN_PATHS[@]}"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "clerk SessionStart hook injects the seed and kicks async glean" {
	cd "$REPO_ROOT"
	grep -q 'clerk glean --async' umbel/hooks/local/clerk-session-start/session-start
	run umbel/hooks/local/clerk-session-start/session-start
	[ "$status" -eq 0 ]
	[[ "$output" == *'"hookEventName": "SessionStart"'* ]]
	[[ "$output" == *'clerk-operating-rules'* ]]
	[[ "$output" == *'clerk backlog next|show|claim|release|return|submit|finish'* ]]
}

@test "presort successor speaks Clerk grammar and demotes criteria-less candidates" {
	cd "$REPO_ROOT"
	presort=umbel/skills/local/clerk-presort/SKILL.md
	grep -q 'clerk inbox list' "$presort"
	grep -q 'clerk inbox pregrill <id>' "$presort"
	grep -q 'A criteria-less ready-looking candidate is \*\*not ready\*\*' "$presort"
	run grep -nE 'bd|beads|tier|repo-visibility' "$presort"
	[ "$status" -eq 1 ]
}

@test "presort successor encodes pregrill delta idempotence" {
	cd "$REPO_ROOT"
	presort=umbel/skills/local/clerk-presort/SKILL.md
	grep -q '\[pregrill:absent\]' "$presort"
	grep -q '\[pregrill:stale\]' "$presort"
	grep -q '\[pregrill:present\]' "$presort"
	grep -q 'A second pass over an unchanged inbox files nothing' "$presort"
}

@test "grill-with-docs loads acceptance playbook guidance" {
	cd "$REPO_ROOT"
	grill=umbel/skills/pocock/grill-with-docs/SKILL.md
	grep -q 'umbel/docs/acceptance-playbook.md' "$grill"
	grep -q 'verbatim strings, exit codes, environment/context signals' "$grill"
	grep -q 'Delivery may add evidence later, but must not invent or narrow the exam' "$grill"
}

@test "umbel sees the clerk generation and can pin clerk-delivery-base" {
	command -v umbel >/dev/null 2>&1 || skip "umbel not installed"
	cd "$REPO_ROOT"
	run env UMBEL_ARTIFACTS_DIR="$REPO_ROOT/umbel" umbel list
	[ "$status" -eq 0 ]
	[[ "$output" == *'clerk-discovery'* ]]
	[[ "$output" == *'clerk-delivery-base'* ]]
	[[ "$output" == *'clerk-delivery-superpowers'* ]]

	project="$BATS_TEST_TMPDIR/apply-project"
	mkdir -p "$project"
	cd "$project"
	run env UMBEL_ARTIFACTS_DIR="$REPO_ROOT/umbel" umbel apply clerk-delivery-base
	[ "$status" -eq 0 ]
	[ "$(cat .umbel-bundle)" = "clerk-delivery-base" ]

	cd "$REPO_ROOT"
	run env UMBEL_ARTIFACTS_DIR="$REPO_ROOT/umbel" umbel build clerk-delivery-superpowers --no-cache
	[ "$status" -eq 0 ]
	built="$(printf '%s\n' "$output" | tail -1)"
	[ "$(find "$built/hooks" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "1" ]
	[ -d "$built/hooks/clerk-session-start" ]
	grep -q 'clerk-session-start' "$built/hooks/hooks.json"
	[ "$(grep -c '"command"[[:space:]]*:' "$built/hooks/hooks.json")" = "1" ]
	run grep -RinE "$OPACITY_TOKEN_RE" "$built/bundle.md" "$built/hooks/clerk-session-start"
	[ "$status" -eq 1 ]
	[ "$output" = "" ]
}
