#!/usr/bin/env bats
# backlog-read.bats — clerk backlog next + backlog show (unit dotfiles-dft.3, read group).
#
# Printed output is load-bearing (ADR 0015), so these tests assert verbatim lines, not just
# exit codes. bd-backed verbs run against a SCRATCH bd db created fresh per test in the bats
# tmp dir (never this repo's real .beads); gh-backed verbs run against a FAKE `gh` placed
# earlier on PATH that logs its argv and returns canned output (same double pattern
# inbox.bats uses). PATH deliberately excludes this repo's personal ~/.config/bin/bd
# auto-sync shim (ADR 0013) — see inbox.bats's header for the rationale.

setup() {
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	# Excludes ~/.config/bin (the ADR 0013 auto-sync shim) on purpose — see header comment.
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	REAL_BD=$(PATH="$BD_MIN_PATH" command -v bd 2>/dev/null || command -v bd)
	export PATH="$BD_MIN_PATH"
}

# ---------------------------------------------------------------- fixtures --

# Scratch git repo + `.clerk` (backlog: bd) + a fresh scratch bd db (never this repo's real
# .beads). Echoes the physical path.
make_bd_repo() { # $1 = subdir name
	local dir="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$dir"
	dir="$(cd "$dir" && pwd -P)"
	git init -q -b main "$dir"
	printf 'backlog: bd\n' >"$dir/.clerk"
	git -C "$dir" add -A
	git -C "$dir" -c user.email=clerk@test -c user.name=clerk commit -q -m fixture
	(cd "$dir" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	printf '%s\n' "$dir"
}

# Scratch git repo + `.clerk` (backlog: gh); no bd involved at all.
make_gh_repo() { # $1 = subdir name
	local dir="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$dir"
	dir="$(cd "$dir" && pwd -P)"
	git init -q -b main "$dir"
	printf 'backlog: gh\n' >"$dir/.clerk"
	git -C "$dir" add -A
	git -C "$dir" -c user.email=clerk@test -c user.name=clerk commit -q -m fixture
	printf '%s\n' "$dir"
}

# A fake `gh` that logs every invocation's argv to $FAKE_GH_LOG (\x1f-joined per call,
# ===CALL=== delimited) and returns canned output driven by $FAKE_GH_LIST_JSON.
make_fake_gh() { # $1 = dir to place the fake gh
	mkdir -p "$1"
	cat >"$1/gh" <<'SHIM'
#!/bin/sh
{
	printf '===CALL===\n'
	for a in "$@"; do printf '%s\x1f' "$a"; done
	printf '\n'
} >>"$FAKE_GH_LOG"
case "$1 $2" in
	"issue list")
		if [ -n "${FAKE_GH_LIST_JSON:-}" ] && [ -f "$FAKE_GH_LIST_JSON" ]; then
			cat "$FAKE_GH_LIST_JSON"
		else
			printf '[]'
		fi
		;;
	"issue view")
		printf 'fake gh issue view: %s\n' "$3"
		;;
	*)
		printf 'fake-gh: unhandled: %s\n' "$*" >&2
		exit 1
		;;
esac
SHIM
	chmod +x "$1/gh"
}

# A `bd` fork that logs every invocation's argv verbatim to $BD_TRACE_LOG (one line per call,
# \x1f-joined) then always proxies through to the real bd — used to assert the read verbs
# invoke bd with --readonly, without changing behaviour.
make_traced_bd() { # $1 = dir to place the shim
	mkdir -p "$1"
	cat >"$1/bd" <<SHIM
#!/bin/sh
{
	for a in "\$@"; do printf '%s\\x1f' "\$a"; done
	printf '\\n'
} >>"\$BD_TRACE_LOG"
exec "$REAL_BD" "\$@"
SHIM
	chmod +x "$1/bd"
}

# A unit with a real Acceptance Criteria section. Echoes the created id.
mk_ac_unit() { # $1 = title
	bd create "$1" --description '## Acceptance Criteria
- does the thing' --silent
}

# -------------------------------------------------------------- backlog next -

@test "backlog next (bd): includes a stage:ready+unblocked bead, excludes a non-ready open bead and a closed one; bd invoked with --readonly" {
	repo=$(make_bd_repo next1)
	tracedbin="$BATS_TEST_TMPDIR/next1-tracedbin"
	make_traced_bd "$tracedbin"
	export BD_TRACE_LOG="$BATS_TEST_TMPDIR/next1.trace"
	: >"$BD_TRACE_LOG"
	export PATH="$tracedbin:$PATH"
	cd "$repo"
	ready_id=$(mk_ac_unit "ready and unblocked")
	bd update "$ready_id" --add-label stage:ready >/dev/null
	notready_id=$(bd create "still in the inbox" --silent)
	closed_id=$(bd create "long done" --silent)
	bd close "$closed_id" --reason wontfix >/dev/null

	run "$CLERK" backlog next
	[ "$status" -eq 0 ]
	[[ "$output" == "Backlog (ready) — 1 item(s):
  $ready_id  ready and unblocked" ]]
	[[ "$output" != *"$notready_id"* ]]
	[[ "$output" != *"$closed_id"* ]]
	grep -q -- '--readonly' "$BD_TRACE_LOG"
}

@test "backlog next (bd): empty ready pool prints (empty)" {
	repo=$(make_bd_repo next2)
	cd "$repo"
	bd create "still in the inbox" --silent >/dev/null
	run "$CLERK" backlog next
	[ "$status" -eq 0 ]
	[ "$output" = "Backlog (ready) — 0 item(s):
  (empty)" ]
}

@test "backlog next (gh): lists ready-for-agent issues, invoking gh with --label ready-for-agent" {
	repo=$(make_gh_repo next3)
	fakebin="$BATS_TEST_TMPDIR/next3-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/next3.log"
	: >"$FAKE_GH_LOG"
	export FAKE_GH_LIST_JSON="$BATS_TEST_TMPDIR/next3.json"
	printf '[{"number":9,"title":"do the thing"}]' >"$FAKE_GH_LIST_JSON"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	run "$CLERK" backlog next
	[ "$status" -eq 0 ]
	[ "$output" = "Backlog (ready) — 1 item(s):
  #9  do the thing" ]
	grep -F -q -- 'issue\x1flist\x1f--label\x1fready-for-agent' "$FAKE_GH_LOG"
}

# -------------------------------------------------------------- backlog show -

@test "backlog show (bd): passes the id through to bd show, invoking bd with --readonly" {
	repo=$(make_bd_repo show1)
	tracedbin="$BATS_TEST_TMPDIR/show1-tracedbin"
	make_traced_bd "$tracedbin"
	export BD_TRACE_LOG="$BATS_TEST_TMPDIR/show1.trace"
	: >"$BD_TRACE_LOG"
	export PATH="$tracedbin:$PATH"
	cd "$repo"
	id=$(bd create "look at the backlog" --silent)
	run "$CLERK" backlog show "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"$id"*"look at the backlog"* ]]
	grep -q -- '--readonly' "$BD_TRACE_LOG"
}

@test "backlog show: missing id is a usage error, exit 2" {
	repo=$(make_bd_repo show2)
	cd "$repo"
	run "$CLERK" backlog show
	[ "$status" -eq 2 ]
	[ "$output" = 'clerk backlog show: missing id — usage: clerk backlog show <id>' ]
}

@test "backlog show (gh): passes the id through to gh issue view" {
	repo=$(make_gh_repo show3)
	fakebin="$BATS_TEST_TMPDIR/show3-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/show3.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	run "$CLERK" backlog show 7
	[ "$status" -eq 0 ]
	[ "$output" = "fake gh issue view: 7" ]
}
