#!/usr/bin/env bats
# Project-gate protocol coverage for Clerk delivery submission.

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
	mkdir -p "$STUB_BIN"
	export PATH="$STUB_BIN:$BD_MIN_PATH"
}

install_gh_stub() {
	cat >"$STUB_BIN/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/gh.calls"
previous=
for arg; do
	case "$previous" in
		--title) printf '%s' "$arg" >"$BATS_TEST_TMPDIR/gh.title" ;;
		--body) printf '%s' "$arg" >"$BATS_TEST_TMPDIR/gh.body" ;;
	esac
	previous="$arg"
done
printf '%s' "${GH_PR_CREATE_OUTPUT-https://github.com/example/repo/pull/1}"
SH
	chmod +x "$STUB_BIN/gh"
}

make_repo() { # $1=name $2=adapter body $3=owner
	local base origin repo adapter="$2" owner="${3:-clerk}"
	base="$BATS_TEST_TMPDIR/$1"
	origin="$base/origin.git"
	repo="$base/repo"
	mkdir -p "$base"
	git init -q --bare -b main "$origin"
	git init -q -b main "$repo"
	git -C "$repo" config user.email clerk@test
	git -C "$repo" config user.name clerk
	git -C "$repo" remote add origin "$origin"
	(cd "$repo" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	printf 'backlog: bd\nproject-gate: gate.json\n' >"$repo/.clerk"
	printf '{"adapter":"gate","submission_owner":"%s"}\n' "$owner" >"$repo/gate.json"
	printf '%s\n' "$adapter" >"$repo/gate"
	chmod +x "$repo/gate"
	git -C "$repo" add .
	git -C "$repo" commit -q -m gate
	git -C "$repo" push -q origin main
	printf '%s\n' "$repo"
}

claimable_work() { # $1=repo $2=acceptance
	local repo="$1" acceptance="${2:-gate acceptance}" id short
	id=$(cd "$repo" && bd create 'gate work' --acceptance "$acceptance" --silent)
	short="${id#*-}"
	git -C "$repo" checkout -q -b "delivery/$short"
	printf '%s\n' "$id"
}

@test "submit fails closed without a project-gate configuration" {
	repo=$(make_repo no_config $'#!/usr/bin/env bash\nexit 0')
	printf 'backlog: bd\n' >"$repo/.clerk"
	git -C "$repo" add .clerk && git -C "$repo" commit -q -m remove-gate
	git -C "$repo" push -q origin main
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"no project-gate configuration"* ]]
}

@test "submit runs the trusted-default adapter, not delivery-branch replacement content" {
	adapter=$'#!/usr/bin/env bash\nset -euo pipefail\nop=$1; request=$(cat); printf "trusted:%s\\n" "$op" >> "$BATS_TEST_TMPDIR/adapter.calls"; head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); jq -cn --arg h "$head" \'{status:"failed",summary:"expected failure",assessed_commit:$h}\''
	repo=$(make_repo trusted "$adapter")
	id=$(claimable_work "$repo")
	printf 'backlog: bd\nproject-gate: evil.json\n' >"$repo/.clerk"
	printf '{"adapter":"gate"}\n' >"$repo/evil.json"
	printf '#!/usr/bin/env bash\nprintf evil >&2\nexit 99\n' >"$repo/gate"
	chmod +x "$repo/gate"
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 6 ]
	[ "$(cat "$BATS_TEST_TMPDIR/adapter.calls")" = "trusted:run" ]
}

@test "a valid failed verdict differs from operational and malformed adapter failures" {
	failed=$'#!/usr/bin/env bash\nrequest=$(cat); head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); jq -cn --arg h "$head" \'{status:"failed",summary:"check failed",assessed_commit:$h}\''
	repo=$(make_repo failed "$failed")
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 6 ]
	[[ "$output" == *"check failed"* ]]
	[ -z "$(git ls-remote --heads origin "delivery/${id#*-}")" ]
	[ ! -e "$BATS_TEST_TMPDIR/gh.calls" ]

	broken=$'#!/usr/bin/env bash\nexit 9'
	repo=$(make_repo broken "$broken")
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"adapter execution failed"* ]]

	malformed=$'#!/usr/bin/env bash\nprintf not-json'
	repo=$(make_repo malformed "$malformed")
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"valid Gate result JSON"* ]]

	missing_run=$'#!/usr/bin/env bash\nrequest=$(cat); head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); jq -cn --arg h "$head" \'{status:"pending",summary:"queued",assessed_commit:$h}\''
	repo=$(make_repo missing_run "$missing_run")
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"pending Gate result requires run.id"* ]]
}

@test "a Clerk-owned passing result hands off the assessed delivery head" {
	adapter=$'#!/usr/bin/env bash\nrequest=$(cat); head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); jq -cn --arg h "$head" \'{status:"passed",summary:"green",assessed_commit:$h}\''
	repo=$(make_repo clerk_pass "$adapter")
	acceptance=$'    indented criterion\n- gate acceptance'
	id=$(claimable_work "$repo" "$acceptance")
	install_gh_stub
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 0 ]
	[ "$(grep -c '^pr create' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
	[ "$(cat "$BATS_TEST_TMPDIR/gh.title")" = "gate work ($id)" ]
	[ "$(cat "$BATS_TEST_TMPDIR/gh.body")" = "$(printf '## Project gate\n\ngreen\n\n## Acceptance criteria\n\n%s' "$acceptance")" ]
	! grep -q -- '--auto-merge' "$BATS_TEST_TMPDIR/gh.calls"
}

@test "submit refuses Work without Acceptance criteria before the Project gate" {
	adapter=$'#!/usr/bin/env bash\ntouch "$BATS_TEST_TMPDIR/adapter-called"'
	repo=$(make_repo missing_acceptance "$adapter")
	id=$(cd "$repo" && bd create 'missing acceptance' --silent)
	git -C "$repo" checkout -q -b "delivery/${id#*-}"
	install_gh_stub
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 2 ]
	[[ "$output" == *"has no acceptance criteria"* ]]
	[ ! -e "$BATS_TEST_TMPDIR/adapter-called" ]
	[ ! -e "$BATS_TEST_TMPDIR/gh.calls" ]
}

@test "submit rejects missing malformed and additional PR creation output" {
	adapter=$'#!/usr/bin/env bash\nrequest=$(cat); head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); jq -cn --arg h "$head" \'{status:"passed",summary:"green",assessed_commit:$h}\''
	for fixture in missing malformed invalid_owner invalid_repo additional; do
		repo=$(make_repo "create_$fixture" "$adapter")
		id=$(claimable_work "$repo")
		install_gh_stub
		case "$fixture" in
			missing) export GH_PR_CREATE_OUTPUT='' ;;
			malformed) export GH_PR_CREATE_OUTPUT='not-a-url' ;;
			invalid_owner) export GH_PR_CREATE_OUTPUT='https://github.com/-owner/repo/pull/1' ;;
			invalid_repo) export GH_PR_CREATE_OUTPUT='https://github.com/owner/./pull/1' ;;
			additional) export GH_PR_CREATE_OUTPUT=$'https://github.com/example/repo/pull/1\nextra' ;;
		esac
		cd "$repo"
		run "$CLERK" backlog submit "$id"
		[ "$status" -eq 5 ]
		[[ "$output" == *"exactly one well-formed GitHub pull-request URL"* ]]
		[[ "$output" != *"submitted $id"* ]]
		unset GH_PR_CREATE_OUTPUT
	done
}

@test "submit reports a Work backend failure without running the Project gate" {
	adapter=$'#!/usr/bin/env bash\ntouch "$BATS_TEST_TMPDIR/adapter-called"'
	repo=$(make_repo backend_failure "$adapter")
	id=$(claimable_work "$repo")
	cat >"$STUB_BIN/bd" <<'SH'
#!/usr/bin/env bash
printf 'not-json'
SH
	chmod +x "$STUB_BIN/bd"
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"Work lookup failed"* ]]
	[ ! -e "$BATS_TEST_TMPDIR/adapter-called" ]
}

@test "pending runs require an id and only reconciliation invokes status" {
	adapter=$'#!/usr/bin/env bash\nset -euo pipefail\nop=$1; request=$(cat); printf "%s\\n" "$op" >> "$BATS_TEST_TMPDIR/adapter.calls"; head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); if [ "$op" = run ]; then jq -cn --arg h "$head" \'{status:"pending",summary:"queued",assessed_commit:$h,run:{id:"run-1"}}\'; else jq -cn --arg h "$head" \'{status:"failed",summary:"reconciled",assessed_commit:$h}\'; fi'
	repo=$(make_repo pending "$adapter")
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/adapter.calls")" = run ]
	run "$CLERK" backlog gate "$id"
	[ "$status" -eq 6 ]
	[ "$(tr '\n' ' ' <"$BATS_TEST_TMPDIR/adapter.calls")" = "run status " ]
}

@test "Clerk-owned passes require the assessed commit to remain checked out" {
	adapter=$'#!/usr/bin/env bash\nrequest=$(cat); worktree=$(printf "%s" "$request" | jq -r .delivery.worktree); head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); git -C "$worktree" commit --allow-empty -qm "gate advanced head"; jq -cn --arg h "$head" \'{status:"passed",summary:"wrong head",assessed_commit:$h}\''
	repo=$(make_repo mismatch "$adapter")
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 5 ]
	[[ "$output" == *"not the current delivery worktree head"* ]]
}

@test "project-gate ownership closes Work only when completion is reported" {
	adapter=$'#!/usr/bin/env bash\nrequest=$(cat); head=$(printf "%s" "$request" | jq -r .delivery.starting_commit); jq -cn --arg h "$head" \'{status:"passed",summary:"delivered",assessed_commit:$h,delivery:{status:"completed"}}\''
	repo=$(make_repo owner "$adapter" project-gate)
	id=$(claimable_work "$repo")
	cd "$repo"
	run "$CLERK" backlog submit "$id"
	[ "$status" -eq 0 ]
	run bd show "$id" --json
	printf '%s' "$output" | jq -e '.[0].status == "closed"' >/dev/null
}

@test "the dotfiles synchronous adapter runs Bats on half the available CPUs" {
	worktree="$BATS_TEST_TMPDIR/worktree"
	mkdir -p "$worktree/bin" "$worktree/tests/clerk"
	export BATS_ARGS="$BATS_TEST_TMPDIR/bats.args"
	cat >"$STUB_BIN/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$BATS_ARGS"
SH
	cat >"$STUB_BIN/shellcheck" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	chmod +x "$STUB_BIN/bats" "$STUB_BIN/shellcheck"
	git init -q -b main "$worktree"
	git -C "$worktree" config user.email clerk@test
	git -C "$worktree" config user.name clerk
	: >"$worktree/bin/tool"
	git -C "$worktree" add . && git -C "$worktree" commit -q -m fixture

	run bash -c 'printf "%s" "{\"delivery\":{\"worktree\":\"$1\"}}" | "$2" run' _ "$worktree" "$BATS_TEST_DIRNAME/../../clerk/project-gate"
	[ "$status" -eq 0 ]
	cpus=$(getconf _NPROCESSORS_ONLN)
	jobs=$((cpus / 2))
	[ "$jobs" -ge 1 ] || jobs=1
	[ "$(cat "$BATS_ARGS")" = "--jobs $jobs tests/clerk" ]
}

@test "the dotfiles synchronous adapter translates selected command failure to a terminal verdict" {
	worktree="$BATS_TEST_TMPDIR/worktree"
	mkdir -p "$worktree/bin" "$worktree/tests/clerk"
	cat >"$STUB_BIN/bats" <<'SH'
#!/usr/bin/env bash
exit 1
SH
	cat >"$STUB_BIN/shellcheck" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	chmod +x "$STUB_BIN/bats" "$STUB_BIN/shellcheck"
	git init -q -b main "$worktree"
	git -C "$worktree" config user.email clerk@test
	git -C "$worktree" config user.name clerk
	: >"$worktree/bin/tool"
	git -C "$worktree" add . && git -C "$worktree" commit -q -m fixture
	run bash -c 'printf "%s" "{\"delivery\":{\"worktree\":\"$1\"}}" | "$2" run' _ "$worktree" "$BATS_TEST_DIRNAME/../../clerk/project-gate"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.status == "failed" and .summary != "" and .assessed_commit != ""' >/dev/null
}
