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
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	export PATH="$BD_MIN_PATH"
}

# ---------------------------------------------------------------- fixtures --

# A scratch bare git repo as 'origin' (seeded with one commit so it is a valid push target),
# plus a clone with a committed `.clerk` (backlog: bd) marker and a fresh scratch bd db. Git
# identity is pinned to a fixed, known actor ("clerk") so bd's default --claim assignee is
# predictable across tests. Echoes the clone's physical path.
make_claim_repo() { # $1 = subdir name
	local base="$BATS_TEST_TMPDIR/$1" origin="" seed="" clone=""
	mkdir -p "$base"
	origin="$base/origin.git"
	seed="$base/seed"
	clone="$base/clone"
	git init -q --bare -b main "$origin"
	git init -q -b main "$seed"
	git -C "$seed" -c user.email=clerk@test -c user.name=clerk commit -q --allow-empty -m seed
	git -C "$seed" remote add origin "$origin"
	git -C "$seed" push -q origin main
	git clone -q "$origin" "$clone"
	clone="$(cd "$clone" && pwd -P)"
	git -C "$clone" config user.email clerk@test
	git -C "$clone" config user.name clerk
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
	run "$CLERK" backlog claim "$id"
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
