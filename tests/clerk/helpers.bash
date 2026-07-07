# tests/clerk/helpers.bash — shared setup helpers for the clerk bats suite.
# shellcheck shell=bash

# git_sandbox: redirect git's global + system config to throwaway locations so the
# scratch fixtures (git init / config / worktree) can never read or write the
# developer's real git config. A dft.3-era delivery leaked `init.defaultBranch`
# into the symlinked ~/.config/git/config because scratch git ran against the real
# global config; GIT_CONFIG_GLOBAL overrides the $HOME/$XDG lookup, so these two
# exports make the whole suite hermetic. Call first in every setup().
git_sandbox() {
	export GIT_CONFIG_SYSTEM=/dev/null
	export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR:?git_sandbox needs BATS_TEST_TMPDIR}/gitconfig"
}
