#!/usr/bin/env bats
# finish-sync.bats — clerk backlog finish + sync reconciler (unit dotfiles-dft.5).

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
	mkdir -p "$STUB_BIN"
	export PATH="$STUB_BIN:$BD_MIN_PATH"
	install_check_stubs
}

install_check_stubs() {
	cat >"$STUB_BIN/bats" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	cat >"$STUB_BIN/shellcheck" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	chmod +x "$STUB_BIN/bats" "$STUB_BIN/shellcheck"
}

make_finish_repo() { # $1=subdir
	local base="$BATS_TEST_TMPDIR/$1" origin seed clone
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
	git -C "$clone" commit -q -m marker
	git -C "$clone" push -q origin main
	(cd "$clone" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	git -C "$clone" add .beads >/dev/null 2>&1 || true
	git -C "$clone" commit -q -m beads-metadata >/dev/null 2>&1 || true
	git -C "$clone" push -q origin main >/dev/null 2>&1 || true
	printf '%s\n' "$clone"
}

mk_claimed_unit() { # echoes id; caller cwd is repo
	local id short
	id=$(bd create 'finish unit' --description '## Acceptance Criteria
- does the thing' --silent)
	bd update "$id" --add-label stage:ready --claim >/dev/null
	short="${id#*-}"
	git branch -q "delivery/$short" origin/main
	git push -q origin "delivery/$short"
	printf '%s\n' "$id"
}

install_gh_pr_stub() { # $1=mode: none|review|fail|merged|multi
	local mode="$1"
	cat >"$STUB_BIN/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/gh.calls"
mode="__MODE__"
if [ "$1 $2" = "pr list" ]; then
	case "$mode" in
		none) json='[]' ;;
		review) json='[{"number":7,"url":"https://example/pr/7","state":"OPEN","mergedAt":"","reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[{"name":"delivery-gate","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefName":"delivery/x","isDraft":false,"updatedAt":"2026-07-10T00:00:00Z"}]' ;;
		pending) json='[{"number":6,"url":"https://example/pr/6","state":"OPEN","mergedAt":"","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"delivery-gate","status":"IN_PROGRESS","conclusion":""}],"headRefName":"delivery/x","isDraft":false,"updatedAt":"2026-07-10T00:00:00Z"}]' ;;
		fail) json='[{"number":8,"url":"https://example/pr/8","state":"OPEN","mergedAt":"","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"delivery-gate","status":"COMPLETED","conclusion":"FAILURE"},{"name":"unit-tests","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefName":"delivery/x","isDraft":false,"updatedAt":"2026-07-10T00:00:00Z"}]' ;;
		merged) json='[{"number":9,"url":"https://example/pr/9","state":"MERGED","mergedAt":"2026-07-10T00:00:00Z","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"delivery-gate","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefName":"delivery/x","isDraft":false,"updatedAt":"2026-07-10T00:00:00Z"}]' ;;
		multi) json='[{"number":5,"url":"https://example/pr/5","state":"CLOSED","mergedAt":"","reviewDecision":"","statusCheckRollup":[],"headRefName":"delivery/x","isDraft":false,"updatedAt":"2026-07-09T00:00:00Z"},{"number":12,"url":"https://example/pr/12","state":"OPEN","mergedAt":"","reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[{"name":"delivery-gate","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefName":"delivery/x","isDraft":false,"updatedAt":"2026-07-10T00:00:00Z"}]' ;;
	esac
	jq_expr=""
	prev=""
	for arg in "$@"; do
		if [ "$prev" = "--jq" ]; then jq_expr="$arg"; fi
		prev="$arg"
	done
	if [ -n "$jq_expr" ]; then
		printf '%s\n' "$json" | jq -r "$jq_expr"
	else
		printf '%s\n' "$json"
	fi
	exit 0
fi
if [ "$1 $2" = "pr merge" ]; then
	echo merge-attempt >>"$BATS_TEST_TMPDIR/gh.calls"
	exit 0
fi
if [ "$1 $2" = "pr checks" ]; then exit 0; fi
exit 0
SH
	sed -i "s/__MODE__/$mode/" "$STUB_BIN/gh"
	chmod +x "$STUB_BIN/gh"
}

@test "finish: no-PR state refuses and prescribes the exact submit invocation" {
	repo=$(make_finish_repo finish_no_pr)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git checkout -q "delivery/$short"
	install_gh_pr_stub none
	run "$CLERK" backlog finish
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: backlog finish refused — no PR found for delivery/$short" ]
	[ "${lines[1]}" = "       run 'clerk backlog submit $id --body-file <path-to-pr-body.md>'" ]
}

@test "finish: awaiting-review reports and exits 0 with no merge attempt" {
	repo=$(make_finish_repo finish_review)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git checkout -q "delivery/$short"
	install_gh_pr_stub review
	run "$CLERK" backlog finish
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: PR #7 for $id is awaiting review — finish will complete after review" ]
	! grep -q 'pr merge' "$BATS_TEST_TMPDIR/gh.calls"
}

@test "finish: pending checks prescribe --watch and exit successfully" {
	repo=$(make_finish_repo finish_pending)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git checkout -q "delivery/$short"
	install_gh_pr_stub pending
	run "$CLERK" backlog finish
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "clerk: PR #6 for $id has pending checks — run 'clerk backlog finish $id --watch' to wait" ]
	[ "${lines[1]}" = "  delivery-gate" ]
}

@test "finish: failing checks output each named failure" {
	repo=$(make_finish_repo finish_fail)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git checkout -q "delivery/$short"
	install_gh_pr_stub fail
	run "$CLERK" backlog finish
	[ "$status" -eq 1 ]
	[[ "$output" == *"clerk: PR #8 for $id has failing checks"* ]]
	[[ "$output" == *"delivery-gate"* ]]
	[[ "$output" != *"unit-tests"* ]]
}

@test "finish: ignores stale closed PRs and reconciles the active PR for the branch" {
	repo=$(make_finish_repo finish_multi)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git checkout -q "delivery/$short"
	install_gh_pr_stub multi
	run "$CLERK" backlog finish
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: PR #12 for $id is awaiting review — finish will complete after review" ]
}

@test "finish: refuses to push an unpublished branch that is behind origin/main" {
	repo=$(make_finish_repo finish_behind)
	cd "$repo"
	id=$(bd create 'behind unit' --description '## Acceptance Criteria
- does the thing' --silent)
	bd update "$id" --claim >/dev/null
	short="${id#*-}"
	git branch -q "delivery/$short" origin/main
	printf 'new base\n' >base.txt
	git add base.txt
	git commit -q -m 'advance main'
	git push -q origin main
	git checkout -q "delivery/$short"
	run "$CLERK" backlog finish
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "clerk: backlog finish refused — delivery/$short is behind origin/main" ]
	[ "${lines[1]}" = "       run 'git rebase origin/main', then rerun 'clerk backlog finish'" ]
	! git -C "$repo" ls-remote --exit-code --heads origin "delivery/$short" >/dev/null 2>&1
}

@test "finish: post-merge cleanup closes the unit, strips stage:ready, and immediate second run is a clean no-op" {
	repo=$(make_finish_repo finish_merged)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git worktree add -q "$repo/.worktrees/$short" "delivery/$short"
	install_gh_pr_stub merged
	cd "$repo/.worktrees/$short"
	run "$CLERK" backlog finish
	[ "$status" -eq 0 ]
	[[ "$output" == *"finished $id — PR #9 merged, delivery/$short cleaned up, unit closed"* ]]
	[ ! -d "$repo/.worktrees/$short" ]
	! git -C "$repo" show-ref --verify --quiet "refs/heads/delivery/$short"
	! git -C "$repo" ls-remote --exit-code --heads origin "delivery/$short" >/dev/null 2>&1
	json=$(bd -C "$repo" show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = closed ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" = null ]
	cd "$repo"
	run "$CLERK" backlog finish "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *"finished $id — PR #9 merged, delivery/$short cleaned up, unit closed"* ]]
	json=$(bd -C "$repo" show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = closed ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" = null ]
}

@test "finish: stage:ready strip is self-verified before success" {
	repo=$(make_finish_repo finish_strip_verify)
	cd "$repo"
	id=$(mk_claimed_unit)
	short="${id#*-}"
	git worktree add -q "$repo/.worktrees/$short" "delivery/$short"
	install_gh_pr_stub merged
	real_bd=$(command -v bd)
	cat >"$STUB_BIN/bd" <<SH
#!/usr/bin/env bash
for arg in "\$@"; do
	if [ "\$arg" = --remove-label ]; then
		exit 0
	fi
done
exec "$real_bd" "\$@"
SH
	chmod +x "$STUB_BIN/bd"
	cd "$repo/.worktrees/$short"
	run "$CLERK" backlog finish
	[ "$status" -eq 5 ]
	[[ "$output" == *"was not confirmed without stage:ready after finish"* ]]
	json=$("$real_bd" -C "$repo" show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = closed ]
	[ "$(jq -r '(.[0].labels // []) | index("stage:ready")' <<<"$json")" != null ]
}

@test "sync: gh-backed repositories warn and skip instead of failing the sweep" {
	repo=$(make_finish_repo sync_gh)
	cd "$repo"
	printf 'backlog: gh\n' >.clerk
	run "$CLERK" sync
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: sync: gh-backed claim sweep is not available in this generation; skipping" ]
}

@test "sync: dangling claim is reported and no PR is created" {
	repo=$(make_finish_repo sync_dangling)
	cd "$repo"
	id=$(bd create 'dangling unit' --description '## Acceptance Criteria
- does the thing' --silent)
	bd update "$id" --claim >/dev/null
	install_gh_pr_stub none
	run "$CLERK" sync
	[ "$status" -eq 0 ]
	[[ "$output" == *"clerk: sync scanning 1 open claim(s)"* ]]
	[[ "$output" == *"$id is claimed but has no delivery/${id#*-} branch/worktree — no PR created"* ]]
	! grep -q 'pr create' "$BATS_TEST_TMPDIR/gh.calls"
}
