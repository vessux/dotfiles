#!/usr/bin/env bats
# backlog-resolve.bats — no-code completion for pickable ready work.

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	export PATH="$BD_MIN_PATH"
}

make_bd_repo() { # $1 = subdir name
	local base="$BATS_TEST_TMPDIR/$1" origin clone
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

mk_ready_unit() { # $1=title
	local id
	id=$(bd create "$1" --acceptance "- satisfied" --silent)
	bd update "$id" --add-label stage:ready >/dev/null
	printf '%s\n' "$id"
}

seed_returned_attempt() { # $1=repo $2=short
	local repo="$1" short="$2" wt="$BATS_TEST_TMPDIR/returned-$short"
	git -C "$repo" branch "returned/$short" main
	git -C "$repo" worktree add -q "$wt" "returned/$short"
	printf 'returned\n' >"$wt/returned.txt"
	git -C "$wt" add returned.txt
	git -C "$wt" commit -q -m returned-attempt
	git -C "$repo" worktree remove "$wt" >/dev/null
	git -C "$repo" push -q origin "returned/$short"
}

@test "backlog resolve closes a pickable ready unit with a distinct no-code reason and note" {
	repo=$(make_bd_repo resolve_ok)
	cd "$repo"
	id=$(mk_ready_unit "no code needed")
	printf 'verified externally' >resolution.txt

	run "$CLERK" backlog resolve "$id" --file resolution.txt
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: resolved $id without delivery" ]
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = closed ]
	[ "$(jq -r '.[0].close_reason' <<<"$json")" = "resolved without delivery" ]
	[[ "$(jq -r '.[0].notes' <<<"$json")" == *"clerk-backlog-resolution:"* ]]
	[[ "$(jq -r '.[0].notes' <<<"$json")" == *"verified externally"* ]]
}

@test "backlog resolve refuses non-pickable and claimed ready units consistently with backlog next" {
	repo=$(make_bd_repo resolve_not_pickable)
	cd "$repo"
	blocked=$(mk_ready_unit "blocked resolve")
	blocker=$(bd create "open blocker" --silent)
	claimed=$(mk_ready_unit "claimed resolve")
	bd dep add "$blocked" "$blocker" >/dev/null
	bd update "$claimed" --claim --actor other-agent >/dev/null

	run "$CLERK" backlog next
	[ "$status" -eq 0 ]
	[[ "$output" != *"$blocked"* ]]
	[[ "$output" != *"$claimed"* ]]

	run bash -c 'printf "note" | "$1" backlog resolve "$2"' _ "$CLERK" "$blocked"
	[ "$status" -eq 2 ]
	[[ "$output" == *"not pickable"* ]]
	[[ "$output" == *"open blocker"* ]]

	run bash -c 'printf "note" | "$1" backlog resolve "$2"' _ "$CLERK" "$claimed"
	[ "$status" -eq 2 ]
	[[ "$output" == *"not pickable"* ]]
	[[ "$output" == *"claimed by other-agent"* ]]
}

@test "backlog resolve requires criteria, non-empty note, and returned branch disposition" {
	repo=$(make_bd_repo resolve_guards)
	cd "$repo"
	no_ac=$(bd create "no ac" --labels stage:ready --silent)
	id=$(mk_ready_unit "returned resolve")
	short="${id#*-}"
	seed_returned_attempt "$repo" "$short"

	run bash -c 'printf "note" | "$1" backlog resolve "$2"' _ "$CLERK" "$no_ac"
	[ "$status" -eq 2 ]
	[[ "$output" == *"no 'Acceptance Criteria'"* ]]

	run "$CLERK" backlog resolve "$id" --file missing.txt
	[ "$status" -eq 2 ]
	[[ "$output" == *"returned/$short exists"* ]]

	run bash -c 'printf "   " | "$1" backlog resolve "$2" --returned keep' _ "$CLERK" "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"note text must be non-empty"* ]]

	run bash -c 'printf "kept evidence" | "$1" backlog resolve "$2" --returned keep' _ "$CLERK" "$id"
	[ "$status" -eq 0 ]
	git -C "$repo" show-ref --verify --quiet "refs/heads/returned/$short"
}
