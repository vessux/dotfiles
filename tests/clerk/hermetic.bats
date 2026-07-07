#!/usr/bin/env bats
# hermetic.bats — proves the suite's git sandbox: scratch git config writes land in
# a throwaway location, never the developer's real global/system config. Guards the
# dft.3-era leak fix (an init.defaultBranch write bled into ~/.config/git/config).

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	export PATH="/usr/local/bin:/usr/bin:/bin"
}

@test "git sandbox: system config is neutralised" {
	[ "$GIT_CONFIG_SYSTEM" = /dev/null ]
}

@test "git sandbox: global config points inside the per-test tmpdir" {
	case "$GIT_CONFIG_GLOBAL" in
		"$BATS_TEST_TMPDIR"/*) : ;;
		*) printf 'GIT_CONFIG_GLOBAL not sandboxed: %s\n' "$GIT_CONFIG_GLOBAL"; return 1 ;;
	esac
}

@test "git sandbox: a --global write lands in the sandbox, not the real config" {
	git config --global clerk.leak.canary tripped
	[ "$(git config --global --get clerk.leak.canary)" = tripped ]
	run grep -q canary "$GIT_CONFIG_GLOBAL"
	[ "$status" -eq 0 ]
}
