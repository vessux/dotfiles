#!/usr/bin/env bats
# core.bats — clerk core dispatcher (unit dotfiles-dft.1).
#
# Printed output is load-bearing (ADR 0015: "error text is prompt engineering"), so these
# tests assert verbatim lines, not just exit codes. All fixtures are scratch git repos in
# bats temp dirs — the real repo's .clerk cutover belongs to unit dotfiles-dft.8, so no
# test reads or writes this repo's own state.

setup() {
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	ESC=$'\033'
	OK_TAG="  ${ESC}[32m[ ok ]${ESC}[0m"
	# shellcheck disable=SC2034 # symmetry with OK/FAIL tags; warn lines not asserted yet
	WARN_TAG="  ${ESC}[33m[warn]${ESC}[0m"
	FAIL_TAG="  ${ESC}[31m[fail]${ESC}[0m"
	NOT_IMPL="is not yet implemented in this generation (see dotfiles-dft epic)"
	ALL_VERBS=(
		"capture" "sync" "glean"
		"inbox list" "inbox show" "inbox dups" "inbox ready" "inbox drop" "inbox pregrill"
		"backlog next" "backlog show" "backlog claim" "backlog release" "backlog submit"
		"backlog finish" "backlog return"
	)
}

# Scratch git repo with an optional .clerk marker, committed so worktrees see it
# (worktrees check out the committed tree). Echoes the PHYSICAL path — clerk resolves the
# root via `git rev-parse --show-toplevel`, which prints symlink-free paths.
make_repo() { # $1 = subdir name, $2 = marker content ('-' = none)
	local dir="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$dir"
	dir="$(cd "$dir" && pwd -P)"
	git init -q -b main "$dir"
	if [ "$2" != "-" ]; then printf '%s\n' "$2" >"$dir/.clerk"; fi
	git -C "$dir" add -A
	git -C "$dir" -c user.email=clerk@test -c user.name=clerk commit -q --allow-empty -m fixture
	printf '%s\n' "$dir"
}

make_worktree() { # $1 = repo, $2 = id; echoes the worktree path
	git -C "$1" worktree add -q "$1/.worktrees/$2" -b "wt-$2"
	printf '%s/.worktrees/%s\n' "$1" "$2"
}

make_fake_bin() { # $1 = dir; drops an executable stub named bd there
	mkdir -p "$1"
	printf '#!/bin/sh\nexit 0\n' >"$1/bd"
	chmod +x "$1/bd"
}

phys() { # echoes the physical path of an existing dir
	(cd "$1" && pwd -P)
}

assert_roster() { # $1 = index of the 'Known verbs:' line in ${lines[@]}
	local i="$1"
	[ "${lines[i]}" = "Known verbs:" ]
	[ "${lines[i + 1]}" = '  capture "<title>" [--stdin|--impediment]' ]
	[ "${lines[i + 2]}" = '  inbox list|show|dups|ready|drop|pregrill' ]
	[ "${lines[i + 3]}" = '  backlog next|show|claim|release|submit|finish|return' ]
	[ "${lines[i + 4]}" = '  sync' ]
	[ "${lines[i + 5]}" = '  doctor [--fix --backend bd|gh]' ]
	[ "${lines[i + 6]}" = '  glean' ]
	[ "${lines[i + 7]}" = "Next: run 'clerk --explain <verb>' to see what a verb does." ]
}

# ------------------------------------------------------------- version ------

@test "--version prints the single-sourced version string" {
	run "$CLERK" --version
	[ "$status" -eq 0 ]
	[ "$output" = "clerk 0.1.0" ]
}

# -------------------------------------------- dispatch: root vs worktree ----

@test "matrix: every roster verb resolves the repo identically from root and worktree" {
	repo=$(make_repo matrix "backlog: bd")
	wt=$(make_worktree "$repo" wt1)
	for v in "${ALL_VERBS[@]}"; do
		cd "$repo"
		# shellcheck disable=SC2086 # word-split $v into noun + verb on purpose
		run "$CLERK" $v
		[ "$status" -eq 3 ]
		[ "$output" = "clerk: '$v' $NOT_IMPL" ]
		cd "$wt"
		# shellcheck disable=SC2086 # word-split $v into noun + verb on purpose
		run "$CLERK" $v
		[ "$status" -eq 3 ]
		[ "$output" = "clerk: '$v' $NOT_IMPL" ]
	done
}

@test "dispatch resolves the repo from a nested subdirectory of a worktree" {
	repo=$(make_repo nested "backlog: bd")
	wt=$(make_worktree "$repo" wt1)
	mkdir -p "$wt/sub/deep"
	cd "$wt/sub/deep"
	# git rev-parse --show-toplevel must still find the worktree root from a nested cwd,
	# so the marker gate passes and the verb reaches its not-implemented refusal (exit 3).
	run "$CLERK" backlog claim
	[ "$status" -eq 3 ]
	[ "$output" = "clerk: 'backlog claim' $NOT_IMPL" ]
}

@test "matrix: doctor resolves the marker from root and from inside the worktree" {
	repo=$(make_repo docmatrix "backlog: bd")
	wt=$(make_worktree "$repo" wt1)
	home="$BATS_TEST_TMPDIR/docmatrix-home"
	mkdir -p "$home"
	home=$(phys "$home")
	cd "$repo"
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"$OK_TAG .clerk marker: backlog: bd ($repo/.clerk)"* ]]
	cd "$wt"
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"$OK_TAG .clerk marker: backlog: bd ($wt/.clerk)"* ]]
}

# --------------------------------------------------- marker gate refusals ---

@test "missing .clerk: dispatching verb refuses with exit 4 and prescribes doctor" {
	repo=$(make_repo nomarker -)
	cd "$repo"
	run "$CLERK" sync
	[ "$status" -eq 4 ]
	[ "$output" = "clerk: missing .clerk marker at $repo/.clerk — run 'clerk doctor' to provision it" ]
}

@test "invalid .clerk: dispatching verb refuses with exit 4 and prescribes doctor" {
	repo=$(make_repo badmarker "backlog: jira")
	cd "$repo"
	run "$CLERK" backlog next
	[ "$status" -eq 4 ]
	[ "$output" = "clerk: invalid .clerk marker at $repo/.clerk — run 'clerk doctor' to diagnose it" ]
}

@test "two directive lines make the marker invalid" {
	repo=$(make_repo twomarker -)
	printf 'backlog: bd\nbacklog: gh\n' >"$repo/.clerk"
	cd "$repo"
	run "$CLERK" glean
	[ "$status" -eq 4 ]
	[ "$output" = "clerk: invalid .clerk marker at $repo/.clerk — run 'clerk doctor' to diagnose it" ]
}

@test "marker tolerates surrounding whitespace and # comments" {
	repo=$(make_repo losemarker -)
	printf '%s\n' \
		'# which backend holds the ready pool (ADR 0017)' \
		'' \
		'   backlog:   bd   # bd for now' >"$repo/.clerk"
	cd "$repo"
	run "$CLERK" capture "a title"
	[ "$status" -eq 3 ] # marker gate passed; refusal is the not-implemented one
	[ "$output" = "clerk: 'capture' $NOT_IMPL" ]
}

@test "outside any git repo: dispatching verb refuses with exit 4" {
	cd /
	run "$CLERK" sync
	[ "$status" -eq 4 ]
	[ "$output" = "clerk: not inside a git repository — cd into the target repo, then run 'clerk doctor'" ]
}

# ------------------------------------------------------------ unknown verbs -

@test "unknown verb: exit 2 and the verbatim roster" {
	run "$CLERK" frobnicate
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: unknown verb 'frobnicate'" ]
	assert_roster 1
}

@test "unknown subverb: exit 2 and the roster" {
	run "$CLERK" inbox nuke
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: unknown verb 'inbox nuke'" ]
	assert_roster 1
}

@test "unknown subverb spanning two adjacent roster words: exit 2 and the roster" {
	# regression: a glob over the roster string misread one argument equal to two
	# adjacent roster words as a known verb (exit 3 instead of 2, no roster)
	repo=$(make_repo adjacent "backlog: bd")
	cd "$repo"
	run "$CLERK" inbox "list show"
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: unknown verb 'inbox list show'" ]
	assert_roster 1
	run "$CLERK" backlog "claim release"
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: unknown verb 'backlog claim release'" ]
	assert_roster 1
}

@test "bare noun: exit 2, names the noun, prints the roster" {
	run "$CLERK" backlog
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: 'backlog' needs a verb" ]
	assert_roster 1
}

@test "no arguments: exit 2 and the roster" {
	run "$CLERK"
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: missing verb" ]
	assert_roster 1
}

@test "unknown verb wins over marker state (checked before the gate)" {
	repo=$(make_repo unkfirst -)
	cd "$repo"
	run "$CLERK" frobnicate
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: unknown verb 'frobnicate'" ]
}

# --------------------------------------------------------------- --explain --

@test "--explain capture: underlying commands + ADR pointer, verbatim" {
	run "$CLERK" --explain capture
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = 'clerk capture — file one raw capture into the inbox' ]
	[ "${lines[1]}" = '  runs: bd create "<title>" [--stdin]           (backlog: bd)' ]
	[ "${lines[2]}" = '        gh issue create --title "<title>"       (backlog: gh)' ]
	[ "${lines[3]}" = '  see:  ADR 0015 — umbel/docs/adr/0015-clerk-opaque-workflow-verb-facade.md' ]
}

@test "--explain backlog submit points at the delivery gate (ADR 0016)" {
	run "$CLERK" --explain backlog submit
	[ "$status" -eq 0 ]
	[[ "$output" == *"gh pr create"* ]]
	[[ "$output" == *"ADR 0016 — umbel/docs/adr/0016-delivery-gate-acceptance-proof-and-judgment-loops.md"* ]]
}

@test "--explain doctor points at the marker manifest (ADR 0017)" {
	run "$CLERK" --explain doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"reads .clerk"* ]]
	[[ "$output" == *"ADR 0017 — umbel/docs/adr/0017-tier-retired-backlog-location-and-merge-gate-axes.md"* ]]
}

@test "trailing --explain (clerk <noun> <verb> --explain) equals the leading form" {
	lead=$("$CLERK" --explain backlog claim)
	trail=$("$CLERK" backlog claim --explain)
	[ "$lead" = "$trail" ]
	[[ "$lead" == *"delivery/<id>"* ]]
	[[ "$lead" == *"ADR 0017"* ]]
}

@test "--explain covers every roster verb, with or without a marker" {
	repo=$(make_repo explnomarker -) # deliberately marker-less
	cd "$repo"
	for v in "${ALL_VERBS[@]}" doctor; do
		# shellcheck disable=SC2086 # word-split $v into noun + verb on purpose
		run "$CLERK" --explain $v
		[ "$status" -eq 0 ]
		[ "${lines[0]}" = "clerk $v — ${lines[0]#clerk "$v" — }" ] # header names the verb
		[[ "$output" == *"  runs: "* ]]
		[[ "$output" == *"  see:  ADR "* ]]
		# 'runs:' must name at least one concrete underlying command (on the runs: line
		# or an 8-space continuation line), never pure prose
		if ! printf '%s\n' "$output" | grep -qE '^(  runs: |        ).*\<(bd|gh|git|flock)\>'; then
			printf "no concrete command in --explain %s output:\n%s\n" "$v" "$output" >&2
			return 1
		fi
	done
}

@test "--explain of an unknown verb: exit 2 and the roster" {
	run "$CLERK" --explain frobnicate
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: unknown verb 'frobnicate'" ]
}

# ------------------------------------------------------------------ doctor --

@test "doctor: all clear on a healthy repo (verbatim 16-color status lines)" {
	repo=$(make_repo dochealthy "backlog: bd")
	home="$BATS_TEST_TMPDIR/dochealthy-home"
	make_fake_bin "$home/.config/bin"
	home=$(phys "$home")
	cd "$repo"
	run env -i HOME="$home" PATH="$home/.config/bin:/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${ESC}[1mclerk doctor${ESC}[0m — $repo" ]
	[[ "$output" == *"$OK_TAG .clerk marker: backlog: bd ($repo/.clerk)"* ]]
	[[ "$output" == *"$OK_TAG bd shim: $home/.config/bin/bd (shim wins PATH resolution)"* ]]
	[[ "$output" == *"$OK_TAG version: clerk 0.1.0 (clerk --version reports the same string)"* ]]
	[ "${lines[${#lines[@]} - 1]}" = "${ESC}[32mclerk doctor: all clear${ESC}[0m" ]
}

@test "doctor: missing marker fails and prints the exact provisioning command" {
	repo=$(make_repo docmissing -)
	home="$BATS_TEST_TMPDIR/docmissing-home"
	mkdir -p "$home"
	home=$(phys "$home")
	cd "$repo"
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 1 ]
	[[ "$output" == *"$FAIL_TAG .clerk marker: missing ($repo/.clerk)"* ]]
	[[ "$output" == *"         provision it: clerk doctor --fix --backend bd   (or --backend gh)"* ]]
	[ "${lines[${#lines[@]} - 1]}" = "${ESC}[31mclerk doctor: 1 problem(s) — fix the [fail] lines above${ESC}[0m" ]
}

@test "doctor --fix --backend gh provisions the marker non-interactively" {
	repo=$(make_repo docfix -)
	home="$BATS_TEST_TMPDIR/docfix-home"
	mkdir -p "$home"
	home=$(phys "$home")
	cd "$repo"
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor --fix --backend gh
	[ "$status" -eq 0 ]
	[[ "$output" == *"$OK_TAG .clerk marker: provisioned backlog: gh ($repo/.clerk)"* ]]
	[[ "$output" == *"         commit .clerk so worktrees and clones see it: git add .clerk && git commit"* ]]
	[ "$(cat "$repo/.clerk")" = "backlog: gh" ]
	# the marker gate now passes: the same verb that would exit 4 reaches not-implemented
	run "$CLERK" backlog next
	[ "$status" -eq 3 ]
	[ "$output" = "clerk: 'backlog next' $NOT_IMPL" ]
}

@test "doctor --fix that cannot write the marker fails loudly, never 'all clear'" {
	repo=$(make_repo docfixdir -)
	mkdir "$repo/.clerk" # a directory at the marker path blocks the provisioning write
	home="$BATS_TEST_TMPDIR/docfixdir-home"
	mkdir -p "$home"
	home=$(phys "$home")
	cd "$repo"
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor --fix --backend bd
	[ "$status" -eq 1 ]
	[[ "$output" == *"$FAIL_TAG .clerk marker: could not provision ($repo/.clerk)"* ]]
	[[ "$output" == *"         check that $repo is writable and .clerk is not a directory"* ]]
	[[ "$output" != *"all clear"* ]]
	# the marker never validated, so dispatch still refuses at the gate
	run "$CLERK" capture "a title"
	[ "$status" -eq 4 ]
	[ "$output" = "clerk: missing .clerk marker at $repo/.clerk — run 'clerk doctor' to provision it" ]
}

@test "doctor --fix without --backend refuses with the exact rerun command" {
	run "$CLERK" doctor --fix
	[ "$status" -eq 2 ]
	[ "$output" = "clerk doctor: --fix requires --backend bd|gh — rerun as 'clerk doctor --fix --backend bd' (or gh)" ]
}

@test "doctor --fix --backend jira refuses: unknown backend" {
	run "$CLERK" doctor --fix --backend jira
	[ "$status" -eq 2 ]
	[ "$output" = "clerk doctor: unknown backend 'jira' — use --backend bd or --backend gh" ]
}

@test "doctor --backend without --fix is a usage error, not silently ignored" {
	run "$CLERK" doctor --backend gh
	[ "$status" -eq 2 ]
	[ "$output" = "clerk doctor: --backend applies only with --fix — rerun with --fix, e.g. 'clerk doctor --fix --backend bd'" ]
}

@test "doctor survives an unset HOME without crashing (set -u safe)" {
	repo=$(make_repo dochome "backlog: bd")
	cd "$repo"
	# No HOME in the environment — the shim-candidate construction must not trip `set -u`.
	# Reaching the version line proves execution passed the HOME-derived shim candidate.
	run env -i PATH="/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *".clerk marker: backlog: bd ($repo/.clerk)"* ]]
	[[ "$output" == *"version: clerk 0.1.0 (clerk --version reports the same string)"* ]]
	[[ "$output" != *"unbound variable"* ]]
}

@test "doctor: invalid marker fails with format guidance; --fix rewrites it" {
	repo=$(make_repo docinvalid "backlog: jira")
	home="$BATS_TEST_TMPDIR/docinvalid-home"
	mkdir -p "$home"
	home=$(phys "$home")
	cd "$repo"
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 1 ]
	[[ "$output" == *"$FAIL_TAG .clerk marker: invalid ($repo/.clerk)"* ]]
	[[ "$output" == *"         expected a single line 'backlog: bd' or 'backlog: gh' (comments after # are fine)"* ]]
	[[ "$output" == *"         rewrite it: clerk doctor --fix --backend bd   (or --backend gh)"* ]]
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor --fix --backend bd
	[ "$status" -eq 0 ]
	[ "$(cat "$repo/.clerk")" = "backlog: bd" ]
}

@test "doctor detects a bd shim shadowed by PATH ordering" {
	repo=$(make_repo docshadow "backlog: bd")
	home="$BATS_TEST_TMPDIR/docshadow-home"
	sysbin="$BATS_TEST_TMPDIR/docshadow-sysbin"
	make_fake_bin "$home/.config/bin" # the shim the user stowed
	make_fake_bin "$sysbin"           # a system bd that wins PATH resolution
	home=$(phys "$home")
	sysbin=$(phys "$sysbin")
	cd "$repo"
	run env -i HOME="$home" PATH="$sysbin:$home/.config/bin:/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 1 ]
	[[ "$output" == *"$FAIL_TAG bd shim: SHADOWED — 'bd' resolves to $sysbin/bd, expected shim $home/.config/bin/bd"* ]]
	[[ "$output" == *"         fix: put $home/.config/bin before $sysbin in PATH"* ]]
}

@test "doctor accepts the repo-local bin/bd as the expected shim" {
	repo=$(make_repo doclocal "backlog: bd")
	home="$BATS_TEST_TMPDIR/doclocal-home"
	mkdir -p "$home"
	home=$(phys "$home")
	make_fake_bin "$repo/bin"
	cd "$repo"
	run env -i HOME="$home" PATH="$repo/bin:/usr/bin:/bin" "$CLERK" doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"$OK_TAG bd shim: $repo/bin/bd (shim wins PATH resolution)"* ]]
}

# -------------------------------------------------------- output discipline -

@test "output discipline: every escape emitted is 16-color ANSI, never 256/truecolor" {
	repo=$(make_repo ansi "backlog: bd")
	norepo=$(make_repo ansi2 -)
	home="$BATS_TEST_TMPDIR/ansi-home"
	sysbin="$BATS_TEST_TMPDIR/ansi-sysbin"
	make_fake_bin "$home/.config/bin"
	make_fake_bin "$sysbin"
	home=$(phys "$home")
	sysbin=$(phys "$sysbin")

	all=""
	run "$CLERK" --version
	all+="$output"$'\n'
	run "$CLERK" --help
	all+="$output"$'\n'
	run "$CLERK" frobnicate
	all+="$output"$'\n'
	run "$CLERK" backlog
	all+="$output"$'\n'
	for v in "${ALL_VERBS[@]}" doctor; do
		# shellcheck disable=SC2086 # word-split $v into noun + verb on purpose
		run "$CLERK" --explain $v
		all+="$output"$'\n'
	done
	cd "$repo"
	run "$CLERK" capture "a title"
	all+="$output"$'\n'
	run env -i HOME="$home" PATH="$home/.config/bin:/usr/bin:/bin" "$CLERK" doctor
	all+="$output"$'\n'
	run env -i HOME="$home" PATH="$sysbin:$home/.config/bin:/usr/bin:/bin" "$CLERK" doctor
	all+="$output"$'\n'
	cd "$norepo"
	run "$CLERK" sync
	all+="$output"$'\n'
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor
	all+="$output"$'\n'
	run env -i HOME="$home" PATH="/usr/bin:/bin" "$CLERK" doctor --fix --backend bd
	all+="$output"$'\n'

	# no 256-color / truecolor SGR anywhere (38;5 / 38;2 / 48;5 / 48;2)
	if printf '%s' "$all" | grep -qE '\[[0-9;]*[34]8;[25];'; then
		echo "forbidden 256/truecolor escape found" >&2
		return 1
	fi
	# colored output was actually captured, and every CSI sequence emitted is from the
	# 16-color set: bold(1), reset(0), fg 30-37 / bright fg 90-97
	seqs=$(printf '%s' "$all" | grep -oE "${ESC}\[[0-9;]*[a-zA-Z]" | sort -u)
	[ -n "$seqs" ]
	while IFS= read -r s; do
		if ! printf '%s' "$s" | grep -qE "^${ESC}\[(0|1|3[0-7]|9[0-7])(;(0|1|3[0-7]|9[0-7]))*m$"; then
			printf 'non-16-color escape emitted: %q\n' "$s" >&2
			return 1
		fi
	done <<<"$seqs"
}
