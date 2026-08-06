#!/usr/bin/env bats

setup() {
	ADAPTER="$BATS_TEST_DIRNAME/../../phyllary/project-gate"
}

make_worktree() {
	local worktree=$1 shellcheck_status=$2
	mkdir -p "$worktree/bin" "$worktree/phyllary" "$worktree/tests/phyllary"
	printf '%s\n' '#!/usr/bin/env bats' '@'"test \"fixture\" { true; }" >"$worktree/tests/phyllary/pass.bats"
	cat >"$worktree/phyllary/project-gate" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	cat >"$BATS_TEST_TMPDIR/shellcheck" <<SH
#!/usr/bin/env bash
exit $shellcheck_status
SH
	chmod +x "$worktree/phyllary/project-gate" "$BATS_TEST_TMPDIR/shellcheck"
	git init -q -b main "$worktree"
	git -C "$worktree" config user.email phyllary@test
	git -C "$worktree" config user.name phyllary
	git -C "$worktree" add .
	git -C "$worktree" commit -qm fixture
}

@test "project gate returns passed for a passing dotfiles worktree" {
	worktree="$BATS_TEST_TMPDIR/pass"
	make_worktree "$worktree" 0
	run env PATH="$BATS_TEST_TMPDIR:$PATH" bash -c 'printf "%s" "{\"delivery\":{\"worktree\":\"$1\"}}" | "$2" run' _ "$worktree" "$ADAPTER"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | tail -1 | jq -e '.status == "passed" and .assessed_commit != ""' >/dev/null
}

@test "project gate returns failed when a project check fails" {
	worktree="$BATS_TEST_TMPDIR/fail"
	make_worktree "$worktree" 1
	run env PATH="$BATS_TEST_TMPDIR:$PATH" bash -c 'printf "%s" "{\"delivery\":{\"worktree\":\"$1\"}}" | "$2" run' _ "$worktree" "$ADAPTER"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | tail -1 | jq -e '.status == "failed" and .assessed_commit != ""' >/dev/null
}
