#!/usr/bin/env bats
# cutover.bats — clerk cutover + local docs (dotfiles-dft.8)

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "repo commits the Clerk marker for this backlog" {
	cd "$REPO_ROOT"
	[ "$(cat .clerk)" = "backlog: bd" ]
}

@test "CLAUDE layer names Clerk, not storage backends" {
	cd "$REPO_ROOT"
	[ "$(readlink CLAUDE.md)" = "AGENTS.md" ]
	grep -q 'clerk' AGENTS.md
	run grep -nEi '(^|[^[:alnum:]_])(bd|beads?|github|gh)([^[:alnum:]_]|$)' AGENTS.md
	[ "$status" -eq 1 ]
	[ "$output" = "" ]
}

@test "zshenv no longer advertises nextdelivery" {
	cd "$REPO_ROOT"
	run grep -n 'nextdelivery' zsh/.zshenv
	[ "$status" -eq 1 ]
	[ "$output" = "" ]
}

@test "clerk repo-meta stays out of git and stow" {
	cd "$REPO_ROOT"
	git check-ignore -q .worktrees/example
	grep -qxF '^\.clerk$' .stow-local-ignore
}

@test "operator issue-tracker doc no longer calls this repo private-tier" {
	cd "$REPO_ROOT"
	run grep -n 'private tier' docs/agents/issue-tracker.md
	[ "$status" -eq 1 ]
	[ "$output" = "" ]
	grep -q 'Clerk-backed backlog' docs/agents/issue-tracker.md
}

@test "nextdelivery is only a Clerk compatibility shim" {
	cd "$REPO_ROOT"
	grep -q "clerk backlog next" bin/nextdelivery
	grep -q "clerk doctor" bin/nextdelivery
	run grep -n 'umbel adopt\|repo-visibility\|bd list\|gh issue' bin/nextdelivery
	[ "$status" -eq 1 ]
	[ "$output" = "" ]
}

@test "old-generation umbel bundles still resolve" {
	command -v umbel >/dev/null 2>&1 || skip "umbel not installed"
	cd "$REPO_ROOT"
	run env UMBEL_ARTIFACTS_DIR="$REPO_ROOT/umbel" umbel show discovery
	[ "$status" -eq 0 ]
	[[ "$output" == *'name: discovery'* ]]
	run env UMBEL_ARTIFACTS_DIR="$REPO_ROOT/umbel" umbel show delivery-superpowers
	[ "$status" -eq 0 ]
	[[ "$output" == *'name: delivery-superpowers'* ]]
}
