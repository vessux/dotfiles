#!/usr/bin/env bats
# claim.bats — clerk backlog claim (unit dotfiles-dft.3).
#
# Printed output is load-bearing (ADR 0015), so these tests assert verbatim lines (the two
# OFFLINE strings are asserted byte-for-byte per the ratified contract), not just exit codes.
# The claim lock is a real git push-CAS, so every fixture is a SCRATCH BARE git repo used as
# 'origin' plus a clone (never this repo's real origin), with its own scratch bd db (never
# this repo's real .beads). PATH deliberately excludes this repo's personal ~/.config/bin/bd
# auto-sync shim (ADR 0013) — same rationale as inbox.bats.

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	export PATH="$BD_MIN_PATH"
}

# ---------------------------------------------------------------- fixtures --

# A scratch bare git repo as 'origin' plus a working repo with a committed `.clerk`
# (backlog: bd) marker and a fresh scratch bd db. Git identity is pinned to a fixed,
# known actor ("clerk") so bd's default --claim assignee is predictable across tests.
# Echoes the working repo's physical path.
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

# A unit with a real Acceptance Criteria section (C4 must pass). Echoes the created id.
mk_ac_unit() { # $1 = title
	bd create "$1" --description '## Acceptance Criteria
- does the thing' --silent
}

# Points `origin` at a path that will never resolve, so `git fetch origin` fails immediately
# (no network hang) — the OFFLINE signal.
break_origin() { # $1 = repo
	git -C "$1" remote set-url origin "$1-gone-nonexistent"
}

seed_returned_attempt() { # $1=repo $2=short $3=file $4=content $5=subject
	local repo="$1" short="$2" file="$3" content="$4" subject="$5" wt
	git -C "$repo" branch "returned/$short" origin/main
	wt="$BATS_TEST_TMPDIR/returned-$short-$RANDOM"
	git -C "$repo" worktree add -q "$wt" "returned/$short"
	printf '%s\n' "$content" >"$wt/$file"
	git -C "$wt" add "$file"
	git -C "$wt" commit -q -m "$subject"
	git -C "$repo" worktree remove "$wt" >/dev/null
	git -C "$repo" push -q origin "returned/$short"
}

advance_main() { # $1=repo $2=file $3=content $4=subject
	local repo="$1" file="$2" content="$3" subject="$4"
	printf '%s\n' "$content" >"$repo/$file"
	git -C "$repo" add "$file"
	git -C "$repo" commit -q -m "$subject"
	git -C "$repo" push -q origin main
}

# ------------------------------------------------------------------- claim --

@test "claim (bd): success prints the ABSOLUTE worktree path as the LAST line; worktree and pushed branch exist; bd claim recorded" {
	repo=$(make_claim_repo claim_a)
	cd "$repo"
	id=$(mk_ac_unit "unit A")
	short="${id#*-}"
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$repo/.worktrees/$short" ]
	[ -d "$repo/.worktrees/$short" ]
	git -C "$repo" fetch -q origin
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].assignee')" = clerk ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "claim (bd): OCCUPIED — exit 5, names the holder, no orphan worktree, no bd mutation on our side" {
	repo=$(make_claim_repo claim_b)
	cd "$repo"
	id=$(mk_ac_unit "unit B")
	short="${id#*-}"
	# Deterministic pre-occupied fixture: push delivery/<short> to origin AND set the scratch
	# bead's assignee to a different holder, both BEFORE our claim call.
	base=$(git -C "$repo" rev-parse origin/main)
	git -C "$repo" push -q origin "$base:refs/heads/delivery/$short"
	bd update "$id" --claim --actor other-agent >/dev/null
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"other-agent"* ]]
	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].assignee')" = other-agent ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "claim (bd): OFFLINE attended — exact LOCAL-ONLY warning, path last line, no push" {
	repo=$(make_claim_repo claim_c)
	cd "$repo"
	id=$(mk_ac_unit "unit C")
	short="${id#*-}"
	break_origin "$repo"
	run env CI= "$CLERK" backlog claim "$id"
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$repo/.worktrees/$short" ]
	[ -d "$repo/.worktrees/$short" ]
	[[ "$output" == *"clerk: OFFLINE - 'delivery/$short' claimed LOCALLY ONLY (not pushed). The branch is the lock; it is compare-and-swapped at first reconnect (clerk submit/sync). If another machine claimed $short meanwhile, that push wins and this local work is discarded. Proceeding, attended."* ]]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].assignee')" = clerk ]
}

@test "claim (bd): OFFLINE in a job context — exact refusal, exit 2, no side effects" {
	repo=$(make_claim_repo claim_d)
	cd "$repo"
	id=$(mk_ac_unit "unit D")
	short="${id#*-}"
	break_origin "$repo"
	run env CLERK_JOB=1 "$CLERK" backlog claim "$id"
	[ "$status" -eq 2 ]
	[ "$output" = "clerk: OFFLINE in a job context - refusing $short: the claim lock needs the remote and no attendant can accept the staleness hazard. Retry when origin is reachable." ]
	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "claim (bd): criteria-less unit refuses, prescribes the grill, exit 2, no side effects" {
	repo=$(make_claim_repo claim_e)
	cd "$repo"
	id=$(bd create "unit E" --description "just prose, no heading" --silent)
	short="${id#*-}"
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"$id has no 'Acceptance Criteria' section"* ]]
	[[ "$output" == *"pregrill"* ]]
	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "claim (bd): re-claim of a unit you already hold is idempotent — already-yours + path, exit 0, no second push" {
	repo=$(make_claim_repo claim_f1)
	cd "$repo"
	id=$(mk_ac_unit "unit F1")
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 0 ]
	first_wt="${lines[-1]}"
	# Break the remote AFTER the first claim: if re-claim ever fell through to SYNC-CHECK
	# instead of short-circuiting, this would surface as the OFFLINE path (different output)
	# or a failed branch-create (already exists) instead of a clean idempotent re-claim.
	break_origin "$repo"
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$first_wt" ]
	[ -d "$first_wt" ]
}

@test "claim (bd): re-claim after the worktree directory was removed recreates it" {
	repo=$(make_claim_repo claim_f2)
	cd "$repo"
	id=$(mk_ac_unit "unit F2")
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 0 ]
	wt="${lines[-1]}"
	rm -rf "$wt"
	[ ! -d "$wt" ]
	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$wt" ]
	[ -d "$wt" ]
}

@test "claim (bd): --from-returned replays the returned attempt onto current main and keeps evidence" {
	repo=$(make_claim_repo claim_from_returned)
	cd "$repo"
	id=$(mk_ac_unit "reuse returned unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" attempt.txt returned-work "returned attempt subject"
	returned_tip=$(git -C "$repo" rev-parse "returned/$short")
	git -C "$repo" branch -D "returned/$short" >/dev/null
	advance_main "$repo" base.txt current-main "advance main after return"
	git -C "$repo" fetch -q origin
	main_tip=$(git -C "$repo" rev-parse origin/main)

	run "$CLERK" backlog claim "$id" --from-returned
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$repo/.worktrees/$short" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(git -C "$repo" merge-base "delivery/$short" origin/main)" = "$main_tip" ]
	[ "$(cat "$repo/.worktrees/$short/base.txt")" = current-main ]
	[ "$(cat "$repo/.worktrees/$short/attempt.txt")" = returned-work ]
	[ "$(git -C "$repo" log -1 --format=%s "delivery/$short")" = "returned attempt subject" ]
	[ "$(git -C "$repo" rev-parse "origin/returned/$short")" = "$returned_tip" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "claim (bd): --from-returned refuses without a returned branch and has no side effects" {
	repo=$(make_claim_repo claim_from_returned_absent)
	cd "$repo"
	id=$(mk_ac_unit "no returned reuse unit")
	short="${id#*-}"
	run "$CLERK" backlog claim "$id" --from-returned
	[ "$status" -eq 2 ]
	[[ "$output" == *"returned/$short was not found"* ]]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "claim (bd): plain claim with returned attempt refuses before side effects" {
	repo=$(make_claim_repo claim_plain_with_returned)
	cd "$repo"
	id=$(mk_ac_unit "plain claim with returned unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" attempt.txt returned-work "returned attempt subject"
	advance_main "$repo" base.txt current-main "advance main for plain claim"
	git -C "$repo" fetch -q origin

	run "$CLERK" backlog claim "$id"
	[ "$status" -eq 2 ]
	[ "$output" = "clerk backlog claim: returned/$short exists — choose how to claim
  reuse returned work: clerk backlog claim $id --from-returned
  start fresh:         clerk backlog claim $id --fresh --returned keep|discard" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ ! -d "$repo/.worktrees/$short" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "claim (bd): --fresh --returned keep claims from main and preserves returned refs" {
	repo=$(make_claim_repo claim_fresh_keep_returned)
	cd "$repo"
	id=$(mk_ac_unit "fresh keep returned unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" attempt.txt returned-work "returned attempt subject"
	advance_main "$repo" base.txt current-main "advance main for fresh claim"
	git -C "$repo" fetch -q origin
	main_tip=$(git -C "$repo" rev-parse origin/main)

	run "$CLERK" backlog claim "$id" --fresh --returned keep
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$repo/.worktrees/$short" ]
	[ "$(git -C "$repo" rev-parse "delivery/$short")" = "$main_tip" ]
	[ "$(cat "$repo/.worktrees/$short/base.txt")" = current-main ]
	[ ! -e "$repo/.worktrees/$short/attempt.txt" ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "claim (bd): --fresh --returned discard claims from main and removes canonical and archived returned refs" {
	repo=$(make_claim_repo claim_fresh_discard_returned)
	cd "$repo"
	id=$(mk_ac_unit "fresh discard returned unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" attempt.txt returned-work "returned attempt subject"
	git -C "$repo" branch "returned/$short-archive" "returned/$short"
	git -C "$repo" push -q origin "returned/$short-archive"
	advance_main "$repo" base.txt current-main "advance main for fresh discard claim"
	git -C "$repo" fetch -q origin
	main_tip=$(git -C "$repo" rev-parse origin/main)

	run "$CLERK" backlog claim "$id" --fresh --returned discard
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$repo/.worktrees/$short" ]
	[ "$(git -C "$repo" rev-parse "delivery/$short")" = "$main_tip" ]
	[ "$(cat "$repo/.worktrees/$short/base.txt")" = current-main ]
	[ ! -e "$repo/.worktrees/$short/attempt.txt" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short-archive"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/returned/$short-archive"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "claim (bd): --fresh with returned attempt requires returned disposition" {
	repo=$(make_claim_repo claim_fresh_missing_disposition)
	cd "$repo"
	id=$(mk_ac_unit "fresh missing disposition unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" attempt.txt returned-work "returned attempt subject"

	run "$CLERK" backlog claim "$id" --fresh
	[ "$status" -eq 2 ]
	[[ "$output" == *"returned/$short exists — choose how to claim"* ]]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "claim (bd): invalid returned claim flag combinations fail before side effects" {
	repo=$(make_claim_repo claim_invalid_returned_flags)
	cd "$repo"
	id=$(mk_ac_unit "invalid returned flags unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" attempt.txt returned-work "returned attempt subject"

	run "$CLERK" backlog claim "$id" --from-returned --fresh
	[ "$status" -eq 2 ]
	[[ "$output" == *"choose only one of --from-returned or --fresh"* ]]
	run "$CLERK" backlog claim "$id" --from-returned --returned keep
	[ "$status" -eq 2 ]
	[[ "$output" == *"--returned is only valid with --fresh"* ]]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ ! -d "$repo/.worktrees/$short" ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]
}

@test "claim (bd): --from-returned conflict leaves the claim lock and worktree for manual resolution" {
	repo=$(make_claim_repo claim_from_returned_conflict)
	cd "$repo"
	printf 'base\n' >conflict.txt
	git add conflict.txt
	git commit -q -m "add conflict base"
	git push -q origin main
	id=$(mk_ac_unit "conflicting returned unit")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short" conflict.txt returned-change "returned conflicting attempt"
	advance_main "$repo" conflict.txt main-change "main conflicting change"
	git -C "$repo" fetch -q origin

	run "$CLERK" backlog claim "$id" --from-returned
	[ "$status" -eq 2 ]
	[[ "$output" == *"claim --from-returned hit conflicts"* ]]
	[[ "$output" == *"conflict.txt"* ]]
	git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/delivery/$short"
	[ -d "$repo/.worktrees/$short" ]
	[ "$(git -C "$repo/.worktrees/$short" diff --name-only --diff-filter=U)" = conflict.txt ]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = in_progress ]
}

@test "claim --explain documents returned-attempt choices" {
	run "$CLERK" backlog claim --explain
	[ "$status" -eq 0 ]
	[[ "$output" == *"--from-returned"* ]]
	[[ "$output" == *"--fresh --returned keep|discard"* ]]
}

@test "claim: missing id is a usage error, exit 2" {
	repo=$(make_claim_repo claim_missing)
	cd "$repo"
	run "$CLERK" backlog claim
	[ "$status" -eq 2 ]
	[[ "$output" == *"missing id"* ]]
}

@test "claim: an id that does not resolve is a usage error, exit 2" {
	repo=$(make_claim_repo claim_nx)
	cd "$repo"
	run "$CLERK" backlog claim nonexistent-zzz
	[ "$status" -eq 2 ]
	[[ "$output" == *"not found"* ]]
}
