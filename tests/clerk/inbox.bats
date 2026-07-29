#!/usr/bin/env bats
# inbox.bats — clerk capture + the six inbox verbs (unit dotfiles-dft.2).
#
# Printed output is load-bearing (ADR 0015), so these tests assert verbatim lines, not just
# exit codes. bd-backed verbs run against a SCRATCH bd db created fresh per test in the bats
# tmp dir (never this repo's real .beads); gh-backed verbs run against a FAKE `gh` placed
# earlier on PATH that logs its argv and returns canned output (same double pattern
# core.bats uses for the shadowed-shim test). PATH deliberately excludes this repo's
# personal ~/.config/bin/bd auto-sync shim (ADR 0013) — that shim triggers a background
# dolt push after every mutating call, which is unwanted noise (and a real-remote risk) for
# a scratch db; resolving straight to the underlying bd binary keeps these tests hermetic.
# In `backlog: gh` fixtures, bd is still initialized because GitHub is only the ready
# delivery backlog; raw capture/inbox storage remains bd.

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	# Excludes ~/.config/bin (the ADR 0013 auto-sync shim) on purpose — see header comment.
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	REAL_BD=$(PATH="$BD_MIN_PATH" command -v bd 2>/dev/null || command -v bd)
	export PATH="$BD_MIN_PATH"
}

# ---------------------------------------------------------------- fixtures --

# Scratch git repo + `.clerk` (backlog: bd) + a fresh scratch bd db (never this repo's real
# .beads). --skip-hooks/--skip-agents/--non-interactive keep the fixture from writing
# Claude/AGENTS.md scaffolding into the scratch dir. Echoes the physical path.
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

add_origin() { # $1 = repo
	local repo="$1" origin="$BATS_TEST_TMPDIR/origin-$(basename "$repo").git"
	git init -q --bare -b main "$origin"
	git -C "$repo" remote add origin "$origin"
	git -C "$repo" push -q origin main
}

mk_returned_branch() { # $1=repo $2=short
	local repo="$1" short="$2"
	git -C "$repo" branch "returned/$short" main
	git -C "$repo" push -q origin "returned/$short"
}

mk_returned_attempt() { # $1=repo $2=short $3=subject
	local repo="$1" short="$2" subject="$3" wt="$BATS_TEST_TMPDIR/returned-$short-$RANDOM"
	git -C "$repo" branch "returned/$short" main
	git -C "$repo" worktree add -q "$wt" "returned/$short"
	printf 'returned work\n' >"$wt/returned.txt"
	git -C "$wt" add returned.txt
	git -C "$wt" -c user.email=clerk@test -c user.name=clerk commit -q -m "$subject"
	git -C "$repo" worktree remove "$wt" >/dev/null
	git -C "$repo" push -q origin "returned/$short"
}

advance_main() { # $1=repo
	local repo="$1"
	printf 'new main\n' >"$repo/main.txt"
	git -C "$repo" add main.txt
	git -C "$repo" -c user.email=clerk@test -c user.name=clerk commit -q -m "advance main"
	git -C "$repo" push -q origin main 2>/dev/null || true
}

# Scratch public-style repo + `.clerk` (backlog: gh) + a fresh scratch bd db.
# GitHub is the delivery backlog; bd remains the raw capture/inbox store.
make_gh_repo() { # $1 = subdir name
	local dir="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$dir"
	dir="$(cd "$dir" && pwd -P)"
	git init -q -b main "$dir"
	printf 'public\n' >"$dir/.repo-visibility"
	printf 'backlog: gh\n' >"$dir/.clerk"
	git -C "$dir" add -A
	git -C "$dir" -c user.email=clerk@test -c user.name=clerk commit -q -m fixture
	(cd "$dir" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	printf '%s\n' "$dir"
}

# A fake `gh` that logs every invocation's argv to $FAKE_GH_LOG (\x1f-joined per call,
# ===CALL=== delimited — readable, grep-able, never parsed field-by-field) and returns
# canned output driven by $FAKE_GH_CREATE_URL / $FAKE_GH_LIST_JSON.
make_traced_bd() { # $1 = dir to place traced bd shim
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
	"issue create")
		printf '%s\n' "${FAKE_GH_CREATE_URL:-https://github.com/acme/repo/issues/42}"
		;;
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
	"issue close")
		printf 'closed\n'
		;;
	"issue comment")
		printf 'commented\n'
		;;
	*)
		printf 'fake-gh: unhandled: %s\n' "$*" >&2
		exit 1
		;;
esac
SHIM
	chmod +x "$1/gh"
}

# A `bd` fork simulating a harness allowlisted to reads + pregrill's single write: any
# invocation carrying --readonly, or the exact `update <id> --append-notes ...` shape,
# proxies through to the real bd; every other shape is refused outright. Logs ALLOWED /
# REFUSED lines to $GUARD_LOG so a test can assert both "it succeeded" and "here is
# everything it actually tried to run". Caller exports REAL_BD and GUARD_LOG.
make_guarded_bd() { # $1 = dir to place the shim
	mkdir -p "$1"
	cat >"$1/bd" <<'SHIM'
#!/bin/sh
log() { [ -n "${GUARD_LOG:-}" ] && printf '%s\n' "ALLOWED: $*" >>"$GUARD_LOG"; }
refuse() {
	[ -n "${GUARD_LOG:-}" ] && printf '%s\n' "REFUSED: $*" >>"$GUARD_LOG"
	echo "guarded-bd: refused: $*" >&2
	exit 13
}
case " $* " in
	*' --readonly '*) log "$@"; exec "$REAL_BD" "$@" ;;
	*' list '*|*' show '*|*' find-duplicates '*) refuse "$@" ;;
	*' update '*' --append-notes '*)
		case " $* " in
			*' --add-label '*|*' --remove-label '*|*' --set-labels '*|*' --status '*|*' --claim '*)
				refuse "$@"
				;;
			*) log "$@"; exec "$REAL_BD" "$@" ;;
		esac
		;;
	*) refuse "$@" ;;
esac
SHIM
	chmod +x "$1/bd"
}

# ---------------------------------------------------------------- capture ---

@test "capture (bd): files a bead and self-verifies before reporting success" {
	repo=$(make_bd_repo cap1)
	cd "$repo"
	run "$CLERK" capture "fix the flaky test"
	[ "$status" -eq 0 ]
	[[ "$output" == "clerk: filed "* ]]
	id="${output#clerk: filed }"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].title')" = "fix the flaky test" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].issue_type')" = task ]
}

@test "capture (bd) --impediment: applies type:impediment, even against a brand-new db with no prior config" {
	repo=$(make_bd_repo cap2)
	cd "$repo"
	# no `bd config set types.custom …` here — capture must self-provision it
	run "$CLERK" capture "the harness denied a benign permission" --impediment
	[ "$status" -eq 0 ]
	[[ "$output" == "clerk: filed "*" (type: impediment)" ]]
	id="${output#clerk: filed }"
	id="${id% (type: impediment)}"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].issue_type')" = impediment ]
}

@test "capture (bd) --impediment is idempotent across repeated captures in the same db" {
	repo=$(make_bd_repo cap3)
	cd "$repo"
	run "$CLERK" capture "first impediment" --impediment
	[ "$status" -eq 0 ]
	run "$CLERK" capture "second impediment" --impediment
	[ "$status" -eq 0 ]
	id="${output#clerk: filed }"
	id="${id% (type: impediment)}"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].issue_type')" = impediment ]
}

@test "capture (bd) --stdin reads the description from stdin" {
	repo=$(make_bd_repo cap4)
	cd "$repo"
	run bash -c "printf 'the reasoning at hand' | \"$CLERK\" capture \"a captured thought\" --stdin"
	[ "$status" -eq 0 ]
	id="${output#clerk: filed }"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].description')" = "the reasoning at hand" ]
}

@test "capture: missing title is a usage error, exit 2" {
	repo=$(make_bd_repo cap5)
	cd "$repo"
	run "$CLERK" capture
	[ "$status" -eq 2 ]
	[ "$output" = 'clerk capture: missing title — usage: clerk capture "<title>" [--stdin|--type <type>|--impediment|--parent <id>|--blocked-by <id>]' ]
}

@test "capture (gh backlog): files raw captures in bd, not GitHub" {
	repo=$(make_gh_repo cap6)
	fakebin="$BATS_TEST_TMPDIR/cap6-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/cap6.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	run "$CLERK" capture "a gh-backed raw capture"
	[ "$status" -eq 0 ]
	[[ "$output" == "clerk: filed "* ]]
	id="${output#clerk: filed }"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].title')" = "a gh-backed raw capture" ]
	[ ! -s "$FAKE_GH_LOG" ]
}

@test "capture (gh backlog) --stdin passes body to bd" {
	repo=$(make_gh_repo cap7)
	cd "$repo"
	run bash -c 'printf "%s\n" "details from stdin" | "$1" capture "a gh-backed stdin capture" --stdin' _ "$CLERK"
	[ "$status" -eq 0 ]
	id="${output#clerk: filed }"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].description')" = "details from stdin" ]
}

# ---------------------------------------------------------------- inbox list -

@test "inbox list (bd) excludes stage:ready beads (the pool is OPEN minus stage:ready)" {
	repo=$(make_bd_repo list1)
	cd "$repo"
	bd create "still in the inbox" --silent >/dev/null
	bd create "already promoted" --labels stage:ready --silent >/dev/null
	run "$CLERK" inbox list
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Inbox (open, not ready) — 1 item(s):" ]
	[[ "$output" == *"still in the inbox"* ]]
	[[ "$output" != *"already promoted"* ]]
}

@test "inbox list (bd): pregrill marker is absent before any pregrill" {
	repo=$(make_bd_repo list2)
	cd "$repo"
	id=$(bd create "untouched" --silent)
	run "$CLERK" inbox list
	[ "$status" -eq 0 ]
	[ "$output" = "Inbox (open, not ready) — 1 item(s):
  $id  [pregrill:absent]  untouched" ]
}

@test "inbox list (bd): pregrill marker is present immediately after pregrilling" {
	repo=$(make_bd_repo list3)
	cd "$repo"
	id=$(bd create "about to be pregrilled" --silent)
	run "$CLERK" inbox pregrill "$id" --decision "d" --premise "p|v" --criterion "c"
	[ "$status" -eq 0 ]
	run "$CLERK" inbox list
	[ "$status" -eq 0 ]
	[[ "$output" == *"$id  [pregrill:present]  about to be pregrilled"* ]]
}

@test "inbox list (bd): pregrill marker flips present->stale after the bead body is edited" {
	repo=$(make_bd_repo list4)
	cd "$repo"
	id=$(bd create "will be edited" --silent)
	run "$CLERK" inbox pregrill "$id"
	[ "$status" -eq 0 ]
	run "$CLERK" inbox list
	[[ "$output" == *"$id  [pregrill:present]"* ]]
	bd update "$id" --description "edited after the pregrill" >/dev/null
	# Test the stale branch deterministically instead of waiting past the production tolerance.
	# A negative test tolerance makes any post-pregrill metadata update stale, even when bd's
	# timestamps are still within the same wall-clock second on fast machines.
	run env CLERK_PREGRILL_STALE_TOLERANCE_S=-1 "$CLERK" inbox list
	[ "$status" -eq 0 ]
	[[ "$output" == *"$id  [pregrill:stale]"* ]]
}

@test "inbox list (bd): --limit 0 forwards unlimited limit and prints rows past the default cap" {
	repo=$(make_bd_repo list_limit0)
	tracedbin="$BATS_TEST_TMPDIR/list-limit0-tracedbin"
	make_traced_bd "$tracedbin"
	export BD_TRACE_LOG="$BATS_TEST_TMPDIR/list-limit0.trace"
	: >"$BD_TRACE_LOG"
	export PATH="$tracedbin:$PATH"
	cd "$repo"
	for n in $(seq 1 55); do
		bd create "visible $n" --silent >/dev/null
	done

	run "$CLERK" inbox list --limit 0
	[ "$status" -eq 0 ]
	[[ "$output" == "Inbox (open, not ready) — 55 item(s):"* ]]
	[[ "$output" == *"visible 55"* ]]
	grep -F -q -- 'list\x1f--status\x1fopen\x1f--exclude-label\x1fstage:ready\x1f--readonly\x1f--json\x1f--limit\x1f0' "$BD_TRACE_LOG"
}

@test "inbox list (bd): --limit forwards a positive numeric limit" {
	repo=$(make_bd_repo list_limit3)
	tracedbin="$BATS_TEST_TMPDIR/list-limit3-tracedbin"
	make_traced_bd "$tracedbin"
	export BD_TRACE_LOG="$BATS_TEST_TMPDIR/list-limit3.trace"
	: >"$BD_TRACE_LOG"
	export PATH="$tracedbin:$PATH"
	cd "$repo"
	for n in $(seq 1 5); do
		bd create "limited $n" --silent >/dev/null
	done

	run "$CLERK" inbox list --limit 3
	[ "$status" -eq 0 ]
	[[ "$output" == *"Inbox (open, not ready) — 3 item(s):"* ]]
	grep -F -q -- '--limit\x1f3' "$BD_TRACE_LOG"
}

@test "inbox list: invalid limits are usage errors before backend calls" {
	repo=$(make_bd_repo list_bad_limit)
	tracedbin="$BATS_TEST_TMPDIR/list-bad-limit-tracedbin"
	make_traced_bd "$tracedbin"
	export BD_TRACE_LOG="$BATS_TEST_TMPDIR/list-bad-limit.trace"
	: >"$BD_TRACE_LOG"
	export PATH="$tracedbin:$PATH"
	cd "$repo"

	run "$CLERK" inbox list --limit nope
	[ "$status" -eq 2 ]
	[ "$output" = 'clerk inbox list: --limit must be a non-negative integer' ]
	[ ! -s "$BD_TRACE_LOG" ]
	run "$CLERK" inbox list --limit
	[ "$status" -eq 2 ]
	[ "$output" = 'clerk inbox list: --limit needs a value — usage: clerk inbox list [--limit <n>]' ]
	[ ! -s "$BD_TRACE_LOG" ]
}

@test "inbox list (bd): empty inbox prints (empty), exit 0" {
	repo=$(make_bd_repo list5)
	cd "$repo"
	run "$CLERK" inbox list
	[ "$status" -eq 0 ]
	[ "$output" = "Inbox (open, not ready) — 0 item(s):
  (empty)" ]
}

@test "inbox list (gh backlog): --limit forwards to bd and never lists GitHub issues" {
	repo=$(make_gh_repo list_gh_limit)
	tracedbin="$BATS_TEST_TMPDIR/list-gh-limit-tracedbin"
	make_traced_bd "$tracedbin"
	fakebin="$BATS_TEST_TMPDIR/list-gh-limit-fakebin"
	make_fake_gh "$fakebin"
	export BD_TRACE_LOG="$BATS_TEST_TMPDIR/list-gh-limit.trace"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/list-gh-limit.log"
	: >"$BD_TRACE_LOG"
	: >"$FAKE_GH_LOG"
	export PATH="$tracedbin:$fakebin:$PATH"
	cd "$repo"
	bd create "bd capture 1" --silent >/dev/null
	bd create "bd capture 2" --silent >/dev/null
	run "$CLERK" inbox list --limit 1
	[ "$status" -eq 0 ]
	[[ "$output" == *"Inbox (open, not ready) — 1 item(s):"* ]]
	grep -F -q -- 'list\x1f--status\x1fopen\x1f--exclude-label\x1fstage:ready\x1f--readonly\x1f--json\x1f--limit\x1f1' "$BD_TRACE_LOG"
	[ ! -s "$FAKE_GH_LOG" ]
}

@test "inbox list (gh backlog): --limit 0 remains bd unlimited" {
	repo=$(make_gh_repo list_gh_limit0)
	cd "$repo"
	bd create "visible after migration" --silent >/dev/null
	run "$CLERK" inbox list --limit 0
	[ "$status" -eq 0 ]
	[[ "$output" == *"visible after migration"* ]]
}

@test "public gh backlog keeps bd raw captures separate from GitHub ready issues" {
	repo=$(make_gh_repo list6)
	fakebin="$BATS_TEST_TMPDIR/list6-fakebin"
	make_fake_gh "$fakebin"
	cat >"$BATS_TEST_TMPDIR/list6.json" <<'JSON'
[
  {"number": 57, "title": "ready GitHub delivery"},
  {"number": 47, "title": "another ready GitHub delivery"}
]
JSON
	export FAKE_GH_LIST_JSON="$BATS_TEST_TMPDIR/list6.json"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/list6.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	id=$(bd create "bd-only raw capture" --silent)
	bd create "ready bead is not the gh backlog" --labels stage:ready --silent >/dev/null

	run "$CLERK" inbox list
	[ "$status" -eq 0 ]
	[ "$output" = "Inbox (open, not ready) — 1 item(s):
  $id  [pregrill:absent]  bd-only raw capture" ]
	[ ! -s "$FAKE_GH_LOG" ]

	run "$CLERK" backlog next
	[ "$status" -eq 0 ]
	[ "$output" = "Backlog (ready) — 2 item(s):
  #57  ready  ready GitHub delivery
  #47  ready  another ready GitHub delivery" ]
	[[ "$output" != *"bd-only raw capture"* ]]
	grep -F -q -- 'issue\x1flist\x1f--label\x1fready-for-agent' "$FAKE_GH_LOG"
}

# ---------------------------------------------------------------- inbox show -

@test "inbox show (bd) shows the bead" {
	repo=$(make_bd_repo show1)
	cd "$repo"
	id=$(bd create "look at me" --silent)
	run "$CLERK" inbox show "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"$id"*"look at me"* ]]
}

@test "inbox show (bd): returned attempt banner names branch, staleness, subject, and disposition" {
	repo=$(make_bd_repo show_returned)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned show unit" --silent)
	short="${id#*-}"
	mk_returned_attempt "$repo" "$short" "returned delivery subject"
	advance_main "$repo"

	run "$CLERK" inbox show "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"$id"*"returned show unit"* ]]
	[[ "$output" == *"returned attempt: returned/$short"* ]]
	[[ "$output" == *"1 commit(s) behind main"* ]]
	[[ "$output" == *"subject: returned delivery subject"* ]]
	[[ "$output" == *"--returned keep|discard"* ]]
}

@test "inbox show (bd): no returned attempt is an exact passthrough" {
	repo=$(make_bd_repo show_no_returned)
	cd "$repo"
	id=$(bd create "plain show unit" --silent)
	expected=$(bd show "$id" --readonly)
	run "$CLERK" inbox show "$id"
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
	[[ "$output" != *"returned attempt"* ]]
}

@test "inbox show (bd): origin-only returned attempt is detected" {
	repo=$(make_bd_repo show_returned_origin_only)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "origin returned show unit" --silent)
	short="${id#*-}"
	mk_returned_attempt "$repo" "$short" "origin-only returned subject"
	git -C "$repo" branch -D "returned/$short" >/dev/null

	run "$CLERK" inbox show "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"returned attempt: returned/$short (origin;"* ]]
	[[ "$output" == *"subject: origin-only returned subject"* ]]
}

@test "inbox show: missing id is a usage error, exit 2" {
	repo=$(make_bd_repo show2)
	cd "$repo"
	run "$CLERK" inbox show
	[ "$status" -eq 2 ]
	[ "$output" = 'clerk inbox show: missing id — usage: clerk inbox show <id> [--json|--pretty]' ]
}

@test "inbox show (gh backlog) shows the bd capture" {
	repo=$(make_gh_repo show3)
	fakebin="$BATS_TEST_TMPDIR/show3-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/show3.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	id=$(bd create "look at my bd capture" --silent)
	run "$CLERK" inbox show "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"$id"*"look at my bd capture"* ]]
	[ ! -s "$FAKE_GH_LOG" ]
}

# ---------------------------------------------------------------- inbox dups -

@test "inbox dups (bd) is cross-pool: a ready bead still shows up as a duplicate of an inbox capture" {
	repo=$(make_bd_repo dups1)
	cd "$repo"
	bd create "fix the login timeout bug" --labels stage:ready --description '## Acceptance Criteria
- x' --silent >/dev/null
	bd create "fix the login timeout bug again" --silent >/dev/null
	run "$CLERK" inbox dups
	[ "$status" -eq 0 ]
	[[ "$output" == "Duplicate candidates — "*" pair(s):"* ]]
	[[ "$output" == *"fix the login timeout bug"* ]]
}

@test "inbox dups (bd): no candidates prints (none), exit 0" {
	repo=$(make_bd_repo dups2)
	cd "$repo"
	bd create "a wholly unique title about zoology" --silent >/dev/null
	run "$CLERK" inbox dups
	[ "$status" -eq 0 ]
	[ "$output" = "Duplicate candidates — 0 pair(s):
  (none)" ]
}

@test "inbox dups (gh backlog) uses the bd capture pool" {
	repo=$(make_gh_repo dups3)
	cd "$repo"
	bd create "fix the auth bug" --silent >/dev/null
	bd create "fix the auth bug again" --silent >/dev/null
	run "$CLERK" inbox dups
	[ "$status" -eq 0 ]
	[[ "$output" == "Duplicate candidates — "* ]]
	[[ "$output" == *"fix the auth bug"* ]]
}

# --------------------------------------------------------------- inbox ready -

@test "inbox ready (bd) on a criteria-less unit: refusal names the missing section, exit 2" {
	repo=$(make_bd_repo ready1)
	cd "$repo"
	id=$(bd create "no criteria here" --description "just prose, no heading" --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"$id has no 'Acceptance Criteria' section"* ]]
}

@test "inbox ready (bd) on a unit with an Acceptance Criteria heading promotes it, self-verified" {
	repo=$(make_bd_repo ready2)
	cd "$repo"
	id=$(bd create "has criteria" --description '## Acceptance Criteria
- does the thing' --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: promoted $id to stage:ready" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].labels | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): a bare 'Acceptance Criteria' line (no markdown heading) also counts" {
	repo=$(make_bd_repo ready3)
	cd "$repo"
	id=$(bd create "has criteria too" --design 'Acceptance Criteria
- does the thing' --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 0 ]
}

@test "inbox ready (bd): prose merely mentioning the phrase is not a section, still refused" {
	repo=$(make_bd_repo ready4)
	cd "$repo"
	id=$(bd create "fake-out" --description "no acceptance criteria yet, sorry" --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"has no 'Acceptance Criteria' section"* ]]
}

@test "inbox ready (bd) on an id with a dedicated acceptance_criteria field (bd create --acceptance) promotes it" {
	repo=$(make_bd_repo ready8)
	cd "$repo"
	id=$(bd create "has acceptance field" --acceptance $'## Acceptance Criteria\n- does the thing' --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: promoted $id to stage:ready" ]
}

@test "inbox ready (bd) on an id whose only criteria live in the dedicated acceptance_criteria field, with no description/design, still promotes" {
	repo=$(make_bd_repo ready9)
	cd "$repo"
	id=$(bd create "bare criteria field" --acceptance "does the thing" --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 0 ]
}

@test "inbox ready (bd) authors design and first-class criteria from files, then promotes" {
	repo=$(make_bd_repo ready11)
	cd "$repo"
	id=$(bd create "needs refinement output" --description "raw capture" --silent)
	printf 'Implementation notes from grill\n' >"$BATS_TEST_TMPDIR/design.md"
	printf -- '- delivered behavior is observable\n' >"$BATS_TEST_TMPDIR/acceptance.md"

	run "$CLERK" inbox ready "$id" --design-file "$BATS_TEST_TMPDIR/design.md" --acceptance-file "$BATS_TEST_TMPDIR/acceptance.md"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: promoted $id to stage:ready" ]
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].design' <<<"$json")" = "Implementation notes from grill" ]
	[ "$(jq -r '.[0].acceptance_criteria' <<<"$json")" = "- delivered behavior is observable" ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" != null ]
}

@test "inbox ready (bd) writes design but still refuses if criteria remain absent" {
	repo=$(make_bd_repo ready12)
	cd "$repo"
	id=$(bd create "design only" --description "raw capture" --silent)
	printf 'Design without an exam\n' >"$BATS_TEST_TMPDIR/design-only.md"

	run "$CLERK" inbox ready "$id" --design-file "$BATS_TEST_TMPDIR/design-only.md"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--acceptance-file"* ]]
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].design' <<<"$json")" = "Design without an exam" ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" = null ]
}

@test "inbox ready (bd) preserves pure-gate behavior for existing first-class criteria" {
	repo=$(make_bd_repo ready13)
	cd "$repo"
	id=$(bd create "already refined" --acceptance "does the thing" --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 0 ]
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): returned branch requires explicit keep or discard" {
	repo=$(make_bd_repo ready_returned_fail)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned ready fail" --acceptance "does the thing" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"

	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--returned keep"* ]]
	[[ "$output" == *"--returned discard"* ]]
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" = null ]
}

@test "inbox ready (bd): returned discard removes local and origin refs before promoting" {
	repo=$(make_bd_repo ready_returned_discard)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned ready discard" --acceptance "does the thing" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"

	run "$CLERK" inbox ready "$id" --returned discard
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: promoted $id to stage:ready" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): returned discard removes canonical and archived returned refs" {
	repo=$(make_bd_repo ready_returned_discard_archives)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned ready discard archives" --acceptance "does the thing" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"
	git -C "$repo" branch "returned/$short-abc1234" main
	git -C "$repo" push -q origin "returned/$short-abc1234"

	run "$CLERK" inbox ready "$id" --returned discard
	[ "$status" -eq 0 ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short-abc1234"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short-abc1234"
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): returned keep preserves refs and promotes" {
	repo=$(make_bd_repo ready_returned_keep)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned ready keep" --acceptance "does the thing" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"

	run "$CLERK" inbox ready "$id" --returned keep
	[ "$status" -eq 0 ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): returned discard is a no-op when no returned branch exists" {
	repo=$(make_bd_repo ready_returned_absent)
	cd "$repo"
	id=$(bd create "no returned branch" --acceptance "does the thing" --silent)
	run "$CLERK" inbox ready "$id" --returned discard
	[ "$status" -eq 0 ]
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): returned discard offline deletes local ref, warns, and still promotes" {
	repo=$(make_bd_repo ready_returned_offline)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned ready offline" --acceptance "does the thing" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"
	git -C "$repo" remote set-url origin "$repo-gone-nonexistent"

	run "$CLERK" inbox ready "$id" --returned discard
	[ "$status" -eq 0 ]
	[[ "$output" == *"OFFLINE"* ]]
	[[ "$output" == *"deferred to sync"* ]]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '(.[0].labels // []) | index("stage:ready")')" != null ]
}

@test "inbox ready (bd): returned disposition has no collateral branches" {
	repo=$(make_bd_repo ready_returned_collateral)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned ready collateral" --acceptance "does the thing" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"
	git -C "$repo" branch "delivery/$short" main
	git -C "$repo" branch "returned/other" main

	run "$CLERK" inbox ready "$id" --returned discard
	[ "$status" -eq 0 ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/other"
}

@test "inbox ready (bd) on an id that does not resolve: bad-id usage error, exit 2 (not the acceptance-criteria refusal)" {
	repo=$(make_bd_repo ready10)
	cd "$repo"
	run "$CLERK" inbox ready does-not-exist-42
	[ "$status" -eq 2 ]
	[ "$output" = "clerk inbox ready: does-not-exist-42 not found — check the id ('clerk inbox list' shows open units)" ]
}

@test "backend command failure surfaces as exit 5 with a prescriptive next action" {
	repo=$(make_bd_repo backendfail1)
	# a bd that fails outright, simulating a broken/unreachable backend
	fake="$BATS_TEST_TMPDIR/failbd"
	mkdir -p "$fake"
	printf '#!/bin/sh\nexit 1\n' >"$fake/bd"
	chmod +x "$fake/bd"
	cd "$repo"
	PATH="$fake:$PATH"
	run "$CLERK" inbox list
	[ "$status" -eq 5 ]
	[[ "$output" == *"clerk: inbox list failed — bd list did not succeed"* ]]
	[[ "$output" == *"run 'clerk doctor' to check the backend"* ]]
}

@test "inbox ready (gh backlog) without --title/--body-file: refusal text prescribes both flags, exit 2" {
	repo=$(make_gh_repo ready5)
	cd "$repo"
	id=$(bd create "ready gh needs args" --silent)
	run "$CLERK" inbox ready "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--title"* ]]
	[[ "$output" == *"--body-file"* ]]
}

@test "inbox ready (gh backlog) creates a ready GitHub issue, then closes the bd capture" {
	repo=$(make_gh_repo ready6)
	fakebin="$BATS_TEST_TMPDIR/ready6-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/ready6.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	id=$(bd create "raw capture to promote" --silent)
	printf 'the groomed body\n' >body.md
	run "$CLERK" inbox ready "$id" --title "promoted title" --body-file body.md
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: promoted $id to #42 (https://github.com/acme/repo/issues/42)" ]
	grep -qF 'issue\x1fcreate\x1f--title\x1fpromoted title\x1f--body-file\x1fbody.md\x1f--label\x1fready-for-agent' "$FAKE_GH_LOG"
	! grep -qF 'issue\x1fclose' "$FAKE_GH_LOG"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].close_reason')" = "promoted to GitHub #42" ]
}

@test "inbox ready: missing id is a usage error, exit 2" {
	repo=$(make_bd_repo ready7)
	cd "$repo"
	run "$CLERK" inbox ready
	[ "$status" -eq 2 ]
	[[ "$output" == "clerk inbox ready: missing id"* ]]
}

# ---------------------------------------------------------------- inbox drop -

@test "inbox drop (bd) closes with reason wontfix, self-verified" {
	repo=$(make_bd_repo drop1)
	cd "$repo"
	id=$(bd create "not worth doing" --silent)
	run "$CLERK" inbox drop "$id"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: dropped $id (wontfix)" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].close_reason')" = wontfix ]
}

@test "inbox drop (bd): returned branch requires explicit keep or discard" {
	repo=$(make_bd_repo drop_returned_fail)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned drop fail" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"

	run "$CLERK" inbox drop "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--returned keep"* ]]
	[[ "$output" == *"--returned discard"* ]]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "inbox drop (bd): returned discard removes branch and closes" {
	repo=$(make_bd_repo drop_returned_discard)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned drop discard" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"

	run "$CLERK" inbox drop "$id" --returned discard
	[ "$status" -eq 0 ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
}

@test "inbox drop (bd): returned discard removes canonical and archived returned refs" {
	repo=$(make_bd_repo drop_returned_discard_archives)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned drop discard archives" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"
	git -C "$repo" branch "returned/$short-abc1234" main
	git -C "$repo" push -q origin "returned/$short-abc1234"

	run "$CLERK" inbox drop "$id" --returned discard
	[ "$status" -eq 0 ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short-abc1234"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short-abc1234"
}

@test "inbox drop (bd): returned keep preserves branch and closes" {
	repo=$(make_bd_repo drop_returned_keep)
	add_origin "$repo"
	cd "$repo"
	id=$(bd create "returned drop keep" --silent)
	short="${id#*-}"
	mk_returned_branch "$repo" "$short"

	run "$CLERK" inbox drop "$id" --returned keep
	[ "$status" -eq 0 ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
}

@test "inbox drop (bd): returned discard is a no-op when no returned branch exists" {
	repo=$(make_bd_repo drop_returned_absent)
	cd "$repo"
	id=$(bd create "drop no returned" --silent)
	run "$CLERK" inbox drop "$id" --returned discard
	[ "$status" -eq 0 ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
}

@test "inbox drop (gh backlog) closes the bd capture" {
	repo=$(make_gh_repo drop2)
	fakebin="$BATS_TEST_TMPDIR/drop2-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/drop2.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	id=$(bd create "drop gh-backed capture" --silent)
	run "$CLERK" inbox drop "$id"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: dropped $id (wontfix)" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = closed ]
	[ ! -s "$FAKE_GH_LOG" ]
}

@test "inbox drop: missing id is a usage error, exit 2" {
	repo=$(make_bd_repo drop3)
	cd "$repo"
	run "$CLERK" inbox drop
	[ "$status" -eq 2 ]
	[ "$output" = 'clerk inbox drop: missing id — usage: clerk inbox drop <id> [--returned keep|discard]' ]
}

# ------------------------------------------------------------- inbox pregrill -

@test "inbox pregrill (bd) is state-neutral: status and labels are byte-identical before/after" {
	repo=$(make_bd_repo preg1)
	cd "$repo"
	id=$(bd create "pregrill target" --labels some-label --silent)
	before=$(bd show "$id" --readonly --json | jq -c '.[0] | {status, labels}')
	run "$CLERK" inbox pregrill "$id" --decision "which backend" --premise "the api is stable|check changelog" --criterion "returns 200"
	[ "$status" -eq 0 ]
	after=$(bd show "$id" --readonly --json | jq -c '.[0] | {status, labels}')
	[ "$before" = "$after" ]
}

@test "inbox pregrill (bd) appends a dated, structured note: open decisions, premises with verification, draft criteria" {
	repo=$(make_bd_repo preg2)
	cd "$repo"
	id=$(bd create "pregrill target" --silent)
	run "$CLERK" inbox pregrill "$id" --decision "which backend" --premise "the api is stable|check changelog" --criterion "returns 200"
	[ "$status" -eq 0 ]
	notes=$(bd show "$id" --readonly --json | jq -r '.[0].notes')
	[[ "$notes" == "clerk-pregrill: "* ]]
	[[ "$notes" == *"Open decisions:"* ]]
	[[ "$notes" == *"- which backend"* ]]
	[[ "$notes" == *"Premises:"* ]]
	[[ "$notes" == *"- the api is stable (verify: check changelog)"* ]]
	[[ "$notes" == *"Draft acceptance criteria:"* ]]
	[[ "$notes" == *"- returns 200"* ]]
}

@test "inbox pregrill (bd) with no decisions/premises/criteria still files a structured note ((none) sections)" {
	repo=$(make_bd_repo preg3)
	cd "$repo"
	id=$(bd create "bare pregrill" --silent)
	run "$CLERK" inbox pregrill "$id"
	[ "$status" -eq 0 ]
	notes=$(bd show "$id" --readonly --json | jq -r '.[0].notes')
	[[ "$notes" == *"Open decisions:"$'\n'"- (none)"* ]]
	[[ "$notes" == *"Premises:"$'\n'"- (none)"* ]]
	[[ "$notes" == *"Draft acceptance criteria:"$'\n'"- (none)"* ]]
}

@test "inbox pregrill (gh backlog) appends notes to the bd capture" {
	repo=$(make_gh_repo preg4)
	fakebin="$BATS_TEST_TMPDIR/preg4-fakebin"
	make_fake_gh "$fakebin"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/preg4.log"
	: >"$FAKE_GH_LOG"
	export PATH="$fakebin:$PATH"
	cd "$repo"
	id=$(bd create "pregrill gh-backed capture" --silent)
	run "$CLERK" inbox pregrill "$id" --decision "d"
	[ "$status" -eq 0 ]
	notes=$(bd show "$id" --readonly --json | jq -r '.[0].notes')
	[[ "$notes" == "clerk-pregrill: "* ]]
	[[ "$notes" == *"- d"* ]]
	[ ! -s "$FAKE_GH_LOG" ]
}

@test "inbox pregrill: missing id is a usage error, exit 2" {
	repo=$(make_bd_repo preg5)
	cd "$repo"
	run "$CLERK" inbox pregrill
	[ "$status" -eq 2 ]
	[[ "$output" == "clerk inbox pregrill: missing id"* ]]
}

# ---------------------------------------------------- readonly / write allowlist ---

@test "backend reads run under --readonly; a fork allowlisted to reads+pregrill cannot execute any other write" {
	repo=$(make_bd_repo guard1)
	cd "$repo"
	id=$(bd create "guarded target" --description '## Acceptance Criteria
- x' --silent)

	guarddir="$BATS_TEST_TMPDIR/guard1-bin"
	make_guarded_bd "$guarddir"
	export REAL_BD
	export GUARD_LOG="$BATS_TEST_TMPDIR/guard1.log"
	: >"$GUARD_LOG"
	export PATH="$guarddir:$PATH"

	run "$CLERK" inbox list
	[ "$status" -eq 0 ]
	run "$CLERK" inbox show "$id"
	[ "$status" -eq 0 ]
	run "$CLERK" inbox dups
	[ "$status" -eq 0 ]
	run "$CLERK" inbox pregrill "$id" --decision d --premise "p|v" --criterion c
	[ "$status" -eq 0 ]

	# nothing was refused — every bd call these four verbs made fit the allowlist
	! grep -q '^REFUSED:' "$GUARD_LOG"
	# the reads all carried --readonly
	grep -qE '^ALLOWED: list .*--readonly' "$GUARD_LOG"
	grep -qE '^ALLOWED: show .*--readonly' "$GUARD_LOG"
	grep -qE '^ALLOWED: find-duplicates .*--readonly' "$GUARD_LOG"
	# pregrill's write is --append-notes alone, and it does NOT carry --readonly
	write_line=$(grep '^ALLOWED: update ' "$GUARD_LOG")
	[[ "$write_line" == *"--append-notes"* ]]
	[[ "$write_line" != *"--readonly"* ]]
	[[ "$write_line" != *"--add-label"* ]]
	[[ "$write_line" != *"--status"* ]]
}
