#!/usr/bin/env bats
# release-return.bats — clerk backlog release / backlog return (unit dotfiles-dft.3, this
# group). Same substrate discipline as claim.bats: a SCRATCH BARE git repo as 'origin' plus a
# clone (never this repo's real origin), its own scratch bd db (never this repo's real
# .beads). PATH deliberately excludes this repo's personal ~/.config/bin/bd auto-sync shim
# (ADR 0013), same rationale as claim.bats/inbox.bats. Printed output is load-bearing (ADR
# 0015): success/refusal text is asserted, not just exit codes.

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	export PATH="$BD_MIN_PATH"
}

# ---------------------------------------------------------------- fixtures --

# A scratch bare git repo as 'origin' plus a working repo with a committed `.clerk`
# (backlog: bd) marker and a fresh scratch bd db. Git identity pinned to a fixed actor
# ("clerk") so bd's --claim assignee is predictable. Echoes the working repo's physical
# path. (Mirrors claim.bats' make_claim_repo exactly — duplicated rather than shared
# across files, same as claim.bats duplicates nothing from inbox.bats.)
make_claim_repo() { # $1 = subdir name
	local base="$BATS_TEST_TMPDIR/$1" origin="" clone=""
	mkdir -p "$base"
	origin="$base/origin.git"
	clone="$base/clone"
	git init -q --bare -b main "$origin"
	git init -q -b main "$clone"
	clone="$(cd "$clone" && pwd -P)"
	git -C "$clone" config user.email clerk@test
	git -C "$clone" config user.name clerk
	git -C "$clone" remote add origin "$origin"
	printf 'backlog: bd\n' >"$clone/.clerk"
	git -C "$clone" add -A
	git -C "$clone" commit -q -m fixture
	git -C "$clone" push -q origin main
	(cd "$clone" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	printf '%s\n' "$clone"
}

# A unit with a real Acceptance Criteria section AND stage:ready (so release/return's "strip
# stage:ready"/"keeps stage:ready" assertions have something to observe), claimable by C4.
# Echoes the created id.
mk_ready_unit() { # $1 = title
	local id
	id=$(bd create "$1" --description '## Acceptance Criteria
- does the thing' --silent)
	bd update "$id" --add-label stage:ready >/dev/null
	printf '%s\n' "$id"
}

# Points `origin` at a path that will never resolve, so `git fetch origin` fails immediately
# (no network hang) — the OFFLINE signal. Mirrors claim.bats' break_origin.
break_origin() { # $1 = repo
	git -C "$1" remote set-url origin "$1-gone-nonexistent"
}

# ---------------------------------------------------------------- release --

@test "release (bd): clean release keeps stage:ready, tears down branch+worktree, reopens unassigned" {
	repo=$(make_claim_repo rel_clean)
	cd "$repo"
	id=$(mk_ready_unit "clean release unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	[ -d "$repo/.worktrees/$short" ]

	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"released $id"* ]]
	[[ "$output" == *"stage:ready kept"* ]]

	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" fetch -q origin
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"

	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = open ]
	[ "$(jq -r '.[0].assignee // ""' <<<"$json")" = "" ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" != null ]
}

@test "release (bd): running from inside the delivery worktree tears down the primary checkout claim" {
	repo=$(make_claim_repo rel_from_worktree)
	cd "$repo"
	id=$(mk_ready_unit "release from worktree unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"

	cd "$wt"
	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[ ! -d "$wt" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" fetch -q origin
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ "$(bd -C "$repo" show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "release (bd): a branch with commits beyond main is refused, exit 2, branch and worktree left intact" {
	repo=$(make_claim_repo rel_work)
	cd "$repo"
	id=$(mk_ready_unit "release with work unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"
	git -C "$wt" -c user.email=clerk@test -c user.name=clerk commit -q --allow-empty -m "did some work"

	run "$CLERK" backlog release "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"delivery/$short has 1 commit(s) beyond main"* ]]
	[[ "$output" == *"submit"* ]]
	[[ "$output" == *"return"* ]]

	[ -d "$wt" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "release (bd): a clean claim releases fine even when local main lags origin/main (dotfiles-dft.3 review)" {
	repo=$(make_claim_repo rel_stale_main)
	cd "$repo"
	id=$(mk_ready_unit "stale main unit")
	short="${id#*-}"

	# Someone else advances origin/main after our clone, without our local main moving.
	other="$BATS_TEST_TMPDIR/rel_stale_main_other"
	git clone -q "$(git -C "$repo" remote get-url origin)" "$other"
	git -C "$other" -c user.email=o@test -c user.name=o commit -q --allow-empty -m "upstream advance"
	git -C "$other" push -q origin main

	local_main_before=$(git -C "$repo" rev-parse main)
	"$CLERK" backlog claim "$id" >/dev/null
	# claim never advances local main — only its own fetch updates origin/main's tracking ref.
	[ "$(git -C "$repo" rev-parse main)" = "$local_main_before" ]
	[ "$(git -C "$repo" rev-list --count main..delivery/"$short")" -gt 0 ]

	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"released $id"* ]]
	[[ "$output" == *"stage:ready kept"* ]]
	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "release (bd): releasing a unit not claimed here is idempotent, exit 0, no error" {
	repo=$(make_claim_repo rel_unheld)
	cd "$repo"
	id=$(mk_ready_unit "never claimed unit")

	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing to release"* ]]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "release (bd): releasing after already releasing is idempotent, exit 0" {
	repo=$(make_claim_repo rel_twice)
	cd "$repo"
	id=$(mk_ready_unit "release twice unit")
	"$CLERK" backlog claim "$id" >/dev/null
	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing to release"* ]]
}

@test "release (bd): OFFLINE attended — local teardown proceeds, remote delete deferred with a warning" {
	repo=$(make_claim_repo rel_offline)
	cd "$repo"
	id=$(mk_ready_unit "offline release unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	break_origin "$repo"

	run env CI= "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"OFFLINE"* ]]
	[[ "$output" == *"deferred to sync"* ]]
	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "release (bd): OFFLINE in a job context — refuses, exit 2, no teardown" {
	repo=$(make_claim_repo rel_offline_job)
	cd "$repo"
	id=$(mk_ready_unit "offline job release unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	break_origin "$repo"

	run env CLERK_JOB=1 "$CLERK" backlog release "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"OFFLINE in a job context"* ]]
	[ -d "$repo/.worktrees/$short" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "release (bd): a dirty worktree fails release WITHOUT releasing the remote CAS lock first (dotfiles-dft.3 review)" {
	repo=$(make_claim_repo rel_dirty_wt)
	cd "$repo"
	id=$(mk_ready_unit "dirty worktree release unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"
	echo x >"$wt/untracked.log"

	run "$CLERK" backlog release "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"could not remove the worktree"* ]]

	# The remote lock must still be held — worktree removal must fail BEFORE the origin branch
	# is deleted, or another machine could push delivery/<short> and win a double-claim.
	git -C "$repo" fetch -q origin
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ -d "$wt" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]

	# Recovery: clean the worktree, rerun — release now succeeds normally.
	rm -f "$wt/untracked.log"
	run "$CLERK" backlog release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"released $id"* ]]
}

@test "release: missing id is a usage error, exit 2" {
	repo=$(make_claim_repo rel_missing)
	cd "$repo"
	run "$CLERK" backlog release
	[ "$status" -eq 2 ]
	[[ "$output" == *"missing id"* ]]
}

@test "release: an id that does not resolve is a usage error, exit 2" {
	repo=$(make_claim_repo rel_nx)
	cd "$repo"
	run "$CLERK" backlog release nonexistent-zzz
	[ "$status" -eq 2 ]
	[[ "$output" == *"not found"* ]]
}

# ----------------------------------------------------------------- return --

@test "return: missing --reason is refused, exit 2, prescribes the flag, no side effects" {
	repo=$(make_claim_repo ret_noreason)
	cd "$repo"
	id=$(mk_ready_unit "return no reason unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null

	run "$CLERK" backlog return "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--reason"* ]]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ -d "$repo/.worktrees/$short" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "return (bd): preserves returned/<short> (local+origin), deletes delivery/<short>, removes worktree, reopens + strips stage:ready, files a VERBATIM-reason impediment capture" {
	repo=$(make_claim_repo ret_full)
	cd "$repo"
	id=$(mk_ready_unit "return full unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"

	reason="the upstream API this depends on was deprecated mid-flight"
	run "$CLERK" backlog return "$id" --reason "$reason"
	[ "$status" -eq 0 ]
	[[ "$output" == *"returned $id"* ]]
	[[ "$output" == *"returned/$short"* ]]

	# delivery/<short> gone (local + remote); returned/<short> present (local + remote)
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	git -C "$repo" fetch -q origin
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"

	# worktree removed
	[ ! -d "$wt" ]

	# unit reopened, unassigned, stage:ready stripped — absent from the ready population,
	# present in the plain inbox pool ('backlog next' is out of this unit's scope and still a
	# stub, so the ready-population check is the underlying label condition it would filter
	# on; 'inbox list' is real and is exercised directly).
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = open ]
	[ "$(jq -r '.[0].assignee // ""' <<<"$json")" = "" ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" = null ]
	run "$CLERK" inbox list
	[[ "$output" == *"$id"* ]]

	# impediment-typed capture: verbatim reason + a returned/<short> reference
	cap_id=$(bd list --status open --json | jq -r --arg t impediment '.[] | select(.issue_type==$t) | .id')
	[ -n "$cap_id" ]
	cap_json=$(bd show "$cap_id" --readonly --json)
	[ "$(jq -r '.[0].issue_type' <<<"$cap_json")" = impediment ]
	body=$(jq -r '.[0].description' <<<"$cap_json")
	[[ "$body" == *"$reason"* ]]
	[[ "$body" == *"returned/$short"* ]]
	[[ "$body" == *"returned from delivery of $id"* ]]
}

@test "return (bd): first return creates canonical returned branch without an archive" {
	repo=$(make_claim_repo ret_first_no_archive)
	cd "$repo"
	id=$(mk_ready_unit "first return no archive unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	run "$CLERK" backlog return "$id" --reason "first return"
	[ "$status" -eq 0 ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	[ -z "$(git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/returned/$short-*")" ]
}

@test "return (bd): second return archives the prior returned attempt and makes the new attempt canonical" {
	repo=$(make_claim_repo ret_second_archive)
	cd "$repo"
	id=$(mk_ready_unit "second return archive unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"
	printf 'first\n' >"$wt/attempt.txt"
	git -C "$wt" add attempt.txt
	git -C "$wt" commit -q -m "first attempt"
	"$CLERK" backlog return "$id" --reason "first miss" >/dev/null
	old_tip=$(git -C "$repo" rev-parse "returned/$short")
	old_suffix=$(git -C "$repo" rev-parse --short "returned/$short")

	bd update "$id" --add-label stage:ready >/dev/null
	"$CLERK" backlog claim "$id" --fresh --returned keep >/dev/null
	wt="$repo/.worktrees/$short"
	printf 'second\n' >"$wt/attempt.txt"
	git -C "$wt" add attempt.txt
	git -C "$wt" commit -q -m "second attempt"
	new_tip=$(git -C "$repo" rev-parse "delivery/$short")

	run "$CLERK" backlog return "$id" --reason "second miss"
	[ "$status" -eq 0 ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short-$old_suffix"
	[ "$(git -C "$repo" rev-parse "returned/$short-$old_suffix")" = "$old_tip" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	[ "$(git -C "$repo" rev-parse "returned/$short")" = "$new_tip" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" fetch -q origin
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short-$old_suffix"
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "return (bd): offline second return archives locally and defers origin updates" {
	repo=$(make_claim_repo ret_second_offline_archive)
	cd "$repo"
	id=$(mk_ready_unit "offline second return archive unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"
	git -C "$wt" commit -q --allow-empty -m "first offline archive attempt"
	"$CLERK" backlog return "$id" --reason "first miss" >/dev/null
	old_tip=$(git -C "$repo" rev-parse "returned/$short")
	old_suffix=$(git -C "$repo" rev-parse --short "returned/$short")

	bd update "$id" --add-label stage:ready >/dev/null
	"$CLERK" backlog claim "$id" --fresh --returned keep >/dev/null
	wt="$repo/.worktrees/$short"
	git -C "$wt" commit -q --allow-empty -m "second offline archive attempt"
	new_tip=$(git -C "$repo" rev-parse "delivery/$short")
	break_origin "$repo"

	run env CI= "$CLERK" backlog return "$id" --reason "offline second miss"
	[ "$status" -eq 0 ]
	[[ "$output" == *"OFFLINE"* ]]
	[[ "$output" == *"deferred to sync"* ]]
	[ "$(git -C "$repo" rev-parse "returned/$short-$old_suffix")" = "$old_tip" ]
	[ "$(git -C "$repo" rev-parse "returned/$short")" = "$new_tip" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "return (bd): running from inside the delivery worktree removes the primary checkout worktree" {
	repo=$(make_claim_repo ret_from_worktree)
	cd "$repo"
	id=$(mk_ready_unit "return from worktree unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"
	git -C "$wt" -c user.email=clerk@test -c user.name=clerk commit -q --allow-empty -m "preserved evidence"

	cd "$wt"
	run "$CLERK" backlog return "$id" --reason "return from inside worktree"
	[ "$status" -eq 0 ]
	[[ "$output" == *"returned $id"* ]]

	[ ! -d "$wt" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" fetch -q origin
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	json=$(bd -C "$repo" show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = open ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" = null ]
}

@test "return (bd): OFFLINE attended — local rename proceeds, remote push/delete deferred with a warning" {
	repo=$(make_claim_repo ret_offline)
	cd "$repo"
	id=$(mk_ready_unit "offline return unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	break_origin "$repo"

	run env CI= "$CLERK" backlog return "$id" --reason "offline test reason"
	[ "$status" -eq 0 ]
	[[ "$output" == *"OFFLINE"* ]]
	[[ "$output" == *"deferred to sync"* ]]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "return (bd): OFFLINE in a job context — refuses, exit 2, no rename, no teardown" {
	repo=$(make_claim_repo ret_offline_job)
	cd "$repo"
	id=$(mk_ready_unit "offline job return unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	break_origin "$repo"

	run env CLERK_JOB=1 "$CLERK" backlog return "$id" --reason "should not matter"
	[ "$status" -eq 2 ]
	[[ "$output" == *"OFFLINE in a job context"* ]]
	[ -d "$repo/.worktrees/$short" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "return (bd): a dirty worktree fails return WITHOUT renaming the branch or touching origin first (dotfiles-dft.3 review)" {
	repo=$(make_claim_repo ret_dirty_wt)
	cd "$repo"
	id=$(mk_ready_unit "dirty worktree return unit")
	short="${id#*-}"
	"$CLERK" backlog claim "$id" >/dev/null
	wt="$repo/.worktrees/$short"
	git -C "$wt" -c user.email=clerk@test -c user.name=clerk commit -q --allow-empty -m "some evidence"
	echo x >"$wt/untracked.log"

	run "$CLERK" backlog return "$id" --reason "dirty worktree repro"
	[ "$status" -eq 5 ]
	[[ "$output" == *"could not remove the worktree"* ]]

	# Half-return must not happen: delivery/<short> still present (local+origin),
	# returned/<short> must NOT exist yet, unit still claimed, no impediment filed.
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" fetch -q origin
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ -d "$wt" ]
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = in_progress ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" != null ]
	cap_count=$(bd list --status open --json | jq -r --arg t impediment '[.[] | select(.issue_type==$t)] | length')
	[ "$cap_count" -eq 0 ]

	# Recovery: clean the worktree, rerun — return now completes normally.
	rm -f "$wt/untracked.log"
	run "$CLERK" backlog return "$id" --reason "dirty worktree repro"
	[ "$status" -eq 0 ]
	[[ "$output" == *"returned $id"* ]]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
}

@test "return: missing id is a usage error, exit 2" {
	repo=$(make_claim_repo ret_missing)
	cd "$repo"
	run "$CLERK" backlog return
	[ "$status" -eq 2 ]
	[[ "$output" == *"missing id"* ]]
}

@test "return: an id that does not resolve is a usage error, exit 2" {
	repo=$(make_claim_repo ret_nx)
	cd "$repo"
	run "$CLERK" backlog return nonexistent-zzz --reason "whatever"
	[ "$status" -eq 2 ]
	[[ "$output" == *"not found"* ]]
}

@test "return: an id not claimed here (no local delivery/<short>) is refused, exit 2" {
	repo=$(make_claim_repo ret_unclaimed)
	cd "$repo"
	id=$(mk_ready_unit "never claimed return unit")
	run "$CLERK" backlog return "$id" --reason "whatever"
	[ "$status" -eq 2 ]
	[[ "$output" == *"no local delivery/"* ]]
}
