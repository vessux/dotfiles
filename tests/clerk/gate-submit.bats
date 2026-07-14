#!/usr/bin/env bats
# gate-submit.bats — clerk backlog gate + submit (unit dotfiles-dft.4).

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
	mkdir -p "$STUB_BIN"
	export PATH="$STUB_BIN:$BD_MIN_PATH"
	install_green_check_stubs
}

install_green_check_stubs() {
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

install_gh_body_stub() { # $1=body file; records calls in $BATS_TEST_TMPDIR/gh.calls
	local body_file="$1"
	cat >"$STUB_BIN/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/gh.calls"
if [ "\$1 \$2" = "pr view" ]; then
	cat "$body_file"
	exit 0
fi
if [ "\$1 \$2" = "pr create" ]; then
	body=""
	prev=""
	for arg in "\$@"; do
		if [ "\$prev" = "--body-file" ]; then body="\$arg"; fi
		prev="\$arg"
	done
	[ -n "\$body" ] && cp "\$body" "$BATS_TEST_TMPDIR/pr-body.md"
	printf 'https://github.example/pr/1\n'
	exit 0
fi
if [ "\$1 \$2" = "pr merge" ]; then
	echo "auto-merge must not be armed" >&2
	exit 99
fi
exit 0
SH
	chmod +x "$STUB_BIN/gh"
}

make_gate_repo() { # $1=subdir, $2=branch short
	local base="$BATS_TEST_TMPDIR/$1" origin clone short="$2"
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
	git -C "$clone" add .clerk
	git -C "$clone" commit -q -m marker
	git -C "$clone" push -q origin main
	git -C "$clone" checkout -q -b "delivery/$short"
	printf '%s\n' "$clone"
}

make_bd_submit_repo() { # $1=subdir
	local repo
	repo=$(make_gate_repo "$1" placeholder)
	git -C "$repo" checkout -q main
	(cd "$repo" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	printf '%s\n' "$repo"
}

write_body() { # $1=file $2=short $3=criterion $4=evidence-or-empty
	local file="$1" short="$2" criterion="$3" evidence="$4"
	{
		printf '## Verification\n\n'
		printf 'Unit: dotfiles-%s\n\n' "$short"
		printf 'Checks:\n'
		printf -- '- bats: ok\n'
		printf -- '- shellcheck: ok\n\n'
		printf '## Acceptance criteria\n'
		printf -- '- %s\n' "$criterion"
		[ -z "$evidence" ] || printf '  evidence: %s\n' "$evidence"
	} >"$file"
}

@test "gate: green on compliant fixture PR" {
	repo=$(make_gate_repo gate_green abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' 'tests/clerk/gate-submit.bats'
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: delivery gate passed" ]
}

@test "gate CI workflow installs the supported parallel runner" {
	cd "$BATS_TEST_DIRNAME/../.."
	grep -q 'apt-get install .* parallel' .github/workflows/delivery-gate.yml
}

@test "gate: uses bats --jobs when a supported parallel runner is available" {
	repo=$(make_gate_repo gate_parallel abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' 'tests/clerk/gate-submit.bats'
	cat >"$STUB_BIN/parallel" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	cat >"$STUB_BIN/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$BATS_TEST_TMPDIR/bats.args"
exit 0
SH
	chmod +x "$STUB_BIN/parallel" "$STUB_BIN/bats"
	cd "$repo"
	run env CLERK_BATS_JOBS=3 "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/bats.args")" = "--jobs 3 tests/clerk" ]
}

@test "gate: does not require the backlog marker" {
	repo=$(make_gate_repo gate_no_marker abc)
	rm "$repo/.clerk"
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' 'tests/clerk/gate-submit.bats'
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 0 ]
	[ "$output" = "clerk: delivery gate passed" ]
}

@test "gate: red on non-delivery branch" {
	repo=$(make_gate_repo gate_branch abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' 'tests/clerk/gate-submit.bats'
	git -C "$repo" checkout -q -b feature/abc
	cd "$repo"
	run "$CLERK" backlog gate --branch feature/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C1 protocol: branch must be delivery/<short>"* ]]
}

@test "gate: red when delivery branch is behind main" {
	repo=$(make_gate_repo gate_behind abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' 'tests/clerk/gate-submit.bats'
	git -C "$repo" checkout -q main
	printf 'new base\n' >"$repo/base.txt"
	git -C "$repo" add base.txt
	git -C "$repo" commit -q -m 'advance main'
	git -C "$repo" push -q origin main
	git -C "$repo" checkout -q delivery/abc
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C1 protocol: branch is behind origin/main"* ]]
}

@test "gate: red on zero linked units" {
	repo=$(make_gate_repo gate_zero abc)
	body="$BATS_TEST_TMPDIR/body.md"
	cat >"$body" <<'EOF'
## Verification

Checks:
- bats: ok

## Acceptance criteria
- does the thing
  evidence: tests/clerk/gate-submit.bats
EOF
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C1 protocol: no linked unit"* ]]
}

@test "gate: red on two linked units" {
	repo=$(make_gate_repo gate_two abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' 'tests/clerk/gate-submit.bats'
	printf 'Unit: dotfiles-other\n' >>"$body"
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C1 protocol: two linked units"* ]]
}

@test "gate: red on missing verification block" {
	repo=$(make_gate_repo gate_c2 abc)
	body="$BATS_TEST_TMPDIR/body.md"
	cat >"$body" <<'EOF'
Unit: dotfiles-abc

Checks:
- bats: ok

## Acceptance criteria
- does the thing
  evidence: tests/clerk/gate-submit.bats
EOF
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C2 verification: missing ## Verification section"* ]]
}

@test "gate: red on criterion without evidence" {
	repo=$(make_gate_repo gate_c4 abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' ''
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C4 acceptance: criterion lacks immediate evidence line: - does the thing"* ]]
}

@test "gate: red on criterion without evidence under all-caps Acceptance Criteria heading" {
	repo=$(make_gate_repo gate_c4_caps abc)
	body="$BATS_TEST_TMPDIR/body.md"
	cat >"$body" <<'EOF'
## Verification

Unit: dotfiles-abc

Checks:
- bats: ok
- shellcheck: ok

## ACCEPTANCE CRITERIA
- does the thing
EOF
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C4 acceptance: criterion lacks immediate evidence line: - does the thing"* ]]
}

@test "gate: preflight and CI entrypoint produce the same verdict on the same fixture" {
	repo=$(make_gate_repo gate_parity abc)
	body="$BATS_TEST_TMPDIR/body.md"
	write_body "$body" abc 'does the thing' ''
	install_gh_body_stub "$body"
	cd "$repo"
	run "$CLERK" backlog gate --branch delivery/abc --body-file "$body"
	local_status="$status"
	local_output="$output"
	run env GITHUB_ACTIONS=true GITHUB_HEAD_REF=delivery/abc GITHUB_BASE_REF=main GITHUB_EVENT_NUMBER=7 "$CLERK" backlog gate
	[ "$status" -eq "$local_status" ]
	[ "$output" = "$local_output" ]
}

@test "proof: prints normalized acceptance criteria as proof JSON skeleton" {
	repo=$(make_bd_submit_repo proof_json)
	cd "$repo"
	id=$(bd create 'proof json unit' --acceptance $'1. does the thing\n2) keeps another promise' --silent)
	run "$CLERK" backlog proof "$id"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.acceptance[0].text == "does the thing"' >/dev/null
	printf '%s' "$output" | jq -e '.acceptance[1].text == "keeps another promise"' >/dev/null
	printf '%s' "$output" | jq -e '.acceptance[0].evidence == ""' >/dev/null
}

@test "submit: proof JSON renders gate-compliant PR body and never arms auto-merge" {
	repo=$(make_bd_submit_repo submit_proof_green)
	cd "$repo"
	id=$(bd create 'submit proof green unit' --acceptance $'1. does the thing\n2) keeps another promise' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	proof="$BATS_TEST_TMPDIR/proof-green.json"
	cat >"$proof" <<'JSON'
{
  "acceptance": [
    {"text": "does the thing", "evidence": "tests/clerk/gate-submit.bats proof path"},
    {"text": "keeps another promise", "evidence": "tests/clerk/gate-submit.bats second proof"}
  ]
}
JSON
	install_gh_body_stub "$BATS_TEST_TMPDIR/pr-body.md"
	run "$CLERK" backlog submit "$id" "$proof"
	[ "$status" -eq 0 ]
	[[ "$output" == *"clerk: delivery gate passed"* ]]
	[[ "$output" == *"clerk: submitted $id — PR created; awaiting review"* ]]
	grep -Fx -- 'Unit: dotfiles-'"$short" "$BATS_TEST_TMPDIR/pr-body.md"
	grep -Eq '^- `bats( --jobs [0-9]+)? tests/clerk` passed$' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -Fx -- '- `shellcheck -S error bin/*` passed' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -Fx -- '- does the thing' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -Fx -- '  evidence: tests/clerk/gate-submit.bats proof path' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -Fx -- '- keeps another promise' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -q -- 'pr create' "$BATS_TEST_TMPDIR/gh.calls"
	! grep -q -- 'pr merge' "$BATS_TEST_TMPDIR/gh.calls"
}

@test "submit: generated proof body records parallel bats command when used" {
	repo=$(make_bd_submit_repo submit_proof_parallel_command)
	cd "$repo"
	id=$(bd create 'submit proof parallel command unit' --acceptance '- does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	cat >"$STUB_BIN/parallel" <<'SH'
#!/usr/bin/env bash
exit 0
SH
	chmod +x "$STUB_BIN/parallel"
	proof="$BATS_TEST_TMPDIR/proof-parallel.json"
	printf '{"acceptance":[{"text":"does the thing","evidence":"parallel evidence"}]}' >"$proof"
	install_gh_body_stub "$BATS_TEST_TMPDIR/pr-body.md"
	run env CLERK_BATS_JOBS=4 "$CLERK" backlog submit "$id" "$proof"
	[ "$status" -eq 0 ]
	grep -Fx -- '- `bats --jobs 4 tests/clerk` passed' "$BATS_TEST_TMPDIR/pr-body.md"
}

@test "submit: proof JSON can be read from stdin" {
	repo=$(make_bd_submit_repo submit_proof_stdin)
	cd "$repo"
	id=$(bd create 'submit proof stdin unit' --acceptance '- does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	install_gh_body_stub "$BATS_TEST_TMPDIR/pr-body.md"
	run bash -c 'printf "%s\n" "{\"acceptance\":[{\"text\":\"does the thing\",\"evidence\":\"stdin evidence\"}]}" | "$1" backlog submit "$2" -' _ "$CLERK" "$id"
	[ "$status" -eq 0 ]
	grep -Fx -- '  evidence: stdin evidence' "$BATS_TEST_TMPDIR/pr-body.md"
}

@test "submit: stale proof JSON fails before PR creation" {
	repo=$(make_bd_submit_repo submit_proof_stale)
	cd "$repo"
	id=$(bd create 'submit proof stale unit' --acceptance '- current criterion' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	proof="$BATS_TEST_TMPDIR/proof-stale.json"
	printf '{"acceptance":[{"text":"old criterion","evidence":"some evidence"}]}' >"$proof"
	install_gh_body_stub "$BATS_TEST_TMPDIR/pr-body.md"
	run "$CLERK" backlog submit "$id" "$proof"
	[ "$status" -eq 2 ]
	[[ "$output" == *"proof JSON is stale at acceptance[0]"* ]]
	[[ "$output" == *"expected: current criterion"* ]]
	[[ "$output" == *"rerun: clerk backlog proof $id"* ]]
	[ ! -f "$BATS_TEST_TMPDIR/pr-body.md" ]
}

@test "submit: proof JSON with missing evidence fails before PR creation" {
	repo=$(make_bd_submit_repo submit_proof_missing_evidence)
	cd "$repo"
	id=$(bd create 'submit proof missing evidence unit' --acceptance '- does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	proof="$BATS_TEST_TMPDIR/proof-missing-evidence.json"
	printf '{"acceptance":[{"text":"does the thing","evidence":"   "}]}' >"$proof"
	install_gh_body_stub "$BATS_TEST_TMPDIR/pr-body.md"
	run "$CLERK" backlog submit "$id" "$proof"
	[ "$status" -eq 2 ]
	[[ "$output" == *"missing evidence for criterion: does the thing"* ]]
	[ ! -f "$BATS_TEST_TMPDIR/pr-body.md" ]
}

@test "submit: refuses when preflight fails and names the failing proof class" {
	repo=$(make_bd_submit_repo submit_red)
	cd "$repo"
	id=$(bd create 'submit red unit' --acceptance '- does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	body="$BATS_TEST_TMPDIR/submit-red.md"
	write_body "$body" "$short" 'does the thing' ''
	run "$CLERK" backlog submit "$id" --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C4 acceptance: criterion lacks immediate evidence line: - does the thing"* ]]
}

@test "submit: first-class numbered criteria reach the gate as normalized bullets" {
	repo=$(make_bd_submit_repo submit_numbered_red)
	cd "$repo"
	id=$(bd create 'submit numbered red unit' --acceptance '1. does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	body="$BATS_TEST_TMPDIR/submit-numbered-red.md"
	{
		printf '## Verification\n\n'
		printf 'Unit: dotfiles-%s\n\n' "$short"
		printf 'Checks:\n- bats: ok\n'
	} >"$body"
	run "$CLERK" backlog submit "$id" --body-file "$body"
	[ "$status" -eq 6 ]
	[[ "$output" == *"C4 acceptance: criterion lacks immediate evidence line: - does the thing"* ]]
	[[ "$output" != *"has no acceptance criteria"* ]]
}

@test "submit: numbered first-class criteria pass when PR body carries normalized evidence" {
	repo=$(make_bd_submit_repo submit_numbered_green)
	cd "$repo"
	id=$(bd create 'submit numbered green unit' --acceptance $'The exam (delivery may add evidence, must not narrow):\n\n1. does the thing\n   with explanatory continuation text\n2) keeps another promise' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	body="$BATS_TEST_TMPDIR/submit-numbered-green.md"
	{
		printf '## Verification\n\n'
		printf 'Unit: dotfiles-%s\n\n' "$short"
		printf 'Checks:\n- bats: ok\n- shellcheck: ok\n\n'
		printf '## Acceptance criteria\n'
		printf -- '- does the thing\n'
		printf '  evidence: tests/clerk/gate-submit.bats\n'
		printf -- '- keeps another promise\n'
		printf '  evidence: tests/clerk/gate-submit.bats\n'
	} >"$body"
	install_gh_body_stub "$body"
	run "$CLERK" backlog submit "$id" --body-file "$body"
	[ "$status" -eq 0 ]
	[[ "$output" == *"clerk: delivery gate passed"* ]]
	[[ "$output" == *"clerk: submitted $id — PR created; awaiting review"* ]]
	grep -Fx -- '- does the thing' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -Fx -- '- keeps another promise' "$BATS_TEST_TMPDIR/pr-body.md"
	! grep -q -- '^1\. does the thing' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -q -- 'pr create' "$BATS_TEST_TMPDIR/gh.calls"
	! grep -q -- 'pr merge' "$BATS_TEST_TMPDIR/gh.calls"
}

@test "submit: single bare first-class criterion uses the same presence semantics as inbox ready" {
	repo=$(make_bd_submit_repo submit_bare_green)
	cd "$repo"
	id=$(bd create 'submit bare green unit' --acceptance 'does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	body="$BATS_TEST_TMPDIR/submit-bare-green.md"
	write_body "$body" "$short" 'does the thing' 'tests/clerk/gate-submit.bats'
	install_gh_body_stub "$body"
	run "$CLERK" backlog submit "$id" --body-file "$body"
	[ "$status" -eq 0 ]
	[[ "$output" == *"clerk: delivery gate passed"* ]]
}

@test "submit: criteria-less units still refuse before preflight" {
	repo=$(make_bd_submit_repo submit_no_criteria)
	cd "$repo"
	id=$(bd create 'submit no criteria unit' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	body="$BATS_TEST_TMPDIR/submit-no-criteria.md"
	write_body "$body" "$short" 'does the thing' 'tests/clerk/gate-submit.bats'
	run "$CLERK" backlog submit "$id" --body-file "$body"
	[ "$status" -eq 2 ]
	[[ "$output" == *"$id has no acceptance criteria"* ]]
}

@test "submit: stamps criteria verbatim into PR body and never arms auto-merge" {
	repo=$(make_bd_submit_repo submit_green)
	cd "$repo"
	id=$(bd create 'submit green unit' --acceptance '- does the thing' --silent)
	short="${id#*-}"
	git checkout -q -b "delivery/$short"
	body="$BATS_TEST_TMPDIR/submit-green.md"
	write_body "$body" "$short" 'does the thing' 'tests/clerk/gate-submit.bats'
	install_gh_body_stub "$body"
	run "$CLERK" backlog submit "$id" --body-file "$body"
	[ "$status" -eq 0 ]
	[[ "$output" == *"clerk: delivery gate passed"* ]]
	[[ "$output" == *"clerk: submitted $id — PR created; awaiting review"* ]]
	grep -Fx -- '- does the thing' "$BATS_TEST_TMPDIR/pr-body.md"
	grep -q -- 'pr create' "$BATS_TEST_TMPDIR/gh.calls"
	! grep -q -- 'pr merge' "$BATS_TEST_TMPDIR/gh.calls"
}
