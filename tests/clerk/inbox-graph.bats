#!/usr/bin/env bats
# inbox-graph.bats — Clerk-native inbox graph primitives (unit dotfiles-2d8o).

setup() {
	source "$BATS_TEST_DIRNAME/helpers.bash"
	git_sandbox
	CLERK="$BATS_TEST_DIRNAME/../../bin/clerk"
	BD_MIN_PATH="/usr/local/bin:/usr/bin:/bin"
	export PATH="$BD_MIN_PATH"
}

make_bd_repo() {
	local dir="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$dir"
	dir="$(cd "$dir" && pwd -P)"
	git init -q -b main "$dir"
	printf 'backlog: bd\n' >"$dir/.clerk"
	git -C "$dir" add -A
	git -C "$dir" -c user.email=clerk@test -c user.name=clerk commit -q -m fixture
	(cd "$dir" && bd init -q --non-interactive --skip-hooks --skip-agents >/dev/null 2>&1)
	printf '%s\n' "$dir"
}

@test "capture supports canonical type, parent, repeatable blocked-by, and --impediment conflict" {
	repo=$(make_bd_repo capture_graph)
	cd "$repo"
	parent=$("$CLERK" capture "map" --type epic | awk '{print $3}')
	blocker=$("$CLERK" capture "first child" --parent "$parent" --type task | awk '{print $3}')
	run "$CLERK" capture "blocked child" --parent "$parent" --blocked-by "$blocker" --type decision
	[ "$status" -eq 0 ]
	child="${output#clerk: filed }"
	json=$(bd show "$child" --readonly --json)
	[ "$(jq -r '.[0].issue_type' <<<"$json")" = decision ]
	[ "$(jq -r '.[0].parent' <<<"$json")" = "$parent" ]
	jq -e --arg blocker "$blocker" '.[0].dependencies | any(.dependency_type == "blocks" and .id == $blocker)' <<<"$json" >/dev/null

	run "$CLERK" capture "bad" --impediment --type task
	[ "$status" -eq 2 ]
	[[ "$output" == *"do not combine"* ]]

	run "$CLERK" capture "missing parent" --blocked-by "$blocker"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--blocked-by requires --parent"* ]]

	run "$CLERK" capture "bad type" --type enhancement
	[ "$status" -eq 2 ]
	[[ "$output" == *"invalid --type"* ]]

	bd config set types.custom research >/dev/null
	run "$CLERK" capture "custom type" --type research
	[ "$status" -eq 0 ]
	custom="${output#clerk: filed }"
	[ "$(bd show "$custom" --readonly --json | jq -r '.[0].issue_type')" = research ]
}

@test "children/frontier/blockers/blocked return normalized JSON and frontier only open unblocked direct children" {
	repo=$(make_bd_repo queries)
	cd "$repo"
	parent=$(bd create "map" --type epic --silent)
	a=$(bd create "a" --parent "$parent" --silent)
	b=$(bd create "b" --parent "$parent" --silent)
	closed=$(bd create "closed" --parent "$parent" --silent)
	ready=$(bd create "ready" --parent "$parent" --labels stage:ready --silent)
	bd dep add "$b" "$a" >/dev/null
	bd close "$closed" --reason done >/dev/null

	run "$CLERK" inbox children "$parent"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.parent.id' <<<"$output")" = "$parent" ]
	[ "$(jq '.items | length' <<<"$output")" -eq 4 ]

	run "$CLERK" inbox frontier "$parent"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.items[].id' <<<"$output")" = "$a" ]

	bd close "$a" --reason done >/dev/null
	run "$CLERK" inbox frontier "$parent" --pretty
	[ "$status" -eq 0 ]
	[ "$(jq -r '.items[].id' <<<"$output")" = "$b" ]
	[[ "$output" == *$'\n  "items"'* ]]

	run "$CLERK" inbox blockers "$b"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.items[0].id' <<<"$output")" = "$a" ]
	run "$CLERK" inbox blocked "$a"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.items[0].id' <<<"$output")" = "$b" ]

	bd close "$parent" --reason done --force >/dev/null
	run "$CLERK" inbox frontier "$parent"
	[ "$status" -eq 2 ]
	[[ "$output" == *"open inbox parent"* ]]
}

@test "parent mutation refuses cycles and dependency-invalidating moves unless dropped" {
	repo=$(make_bd_repo parent_mutation)
	cd "$repo"
	p1=$(bd create "p1" --type epic --silent)
	p2=$(bd create "p2" --type epic --silent)
	a=$(bd create "a" --parent "$p1" --silent)
	b=$(bd create "b" --parent "$p1" --silent)
	bd dep add "$b" "$a" >/dev/null

	run "$CLERK" inbox parent set "$p1" "$a"
	[ "$status" -eq 2 ]
	[[ "$output" == *"parent cycle"* ]]

	run "$CLERK" inbox parent set "$b" "$p2"
	[ "$status" -eq 2 ]
	[[ "$output" == *"--drop-invalid-deps"* ]]
	[ "$(bd show "$b" --readonly --json | jq -r '.[0].parent')" = "$p1" ]

	run "$CLERK" inbox parent set "$b" "$p2" --drop-invalid-deps
	[ "$status" -eq 0 ]
	[ "$(bd show "$b" --readonly --json | jq -r '.[0].parent')" = "$p2" ]
	! bd show "$b" --readonly --json | jq -e --arg a "$a" '.[0].dependencies | any(.dependency_type == "blocks" and .id == $a)' >/dev/null

	run "$CLERK" inbox parent clear "$b"
	[ "$status" -eq 0 ]
	[ "$(bd show "$b" --readonly --json | jq -r '.[0].parent // ""')" = "" ]
}

@test "dependency mutation is sibling-only and refuses cycles" {
	repo=$(make_bd_repo dep_mutation)
	cd "$repo"
	p=$(bd create "p" --type epic --silent)
	other=$(bd create "other" --type epic --silent)
	a=$(bd create "a" --parent "$p" --silent)
	b=$(bd create "b" --parent "$p" --silent)
	c=$(bd create "c" --parent "$other" --silent)

	run "$CLERK" inbox dep add "$b" "$a"
	[ "$status" -eq 0 ]
	jq -e --arg a "$a" '.[0].dependencies | any(.dependency_type == "blocks" and .id == $a)' < <(bd show "$b" --readonly --json) >/dev/null

	run "$CLERK" inbox dep add "$a" "$b"
	[ "$status" -eq 2 ]
	[[ "$output" == *"dependency cycle"* ]]

	run "$CLERK" inbox dep add "$a" "$c"
	[ "$status" -eq 2 ]
	[[ "$output" == *"sibling-only"* ]]

	run "$CLERK" inbox dep remove "$b" "$a"
	[ "$status" -eq 0 ]
	! bd show "$b" --readonly --json | jq -e --arg a "$a" '.[0].dependencies | any(.dependency_type == "blocks" and .id == $a)' >/dev/null

	bd close "$a" --reason done >/dev/null
	run "$CLERK" inbox dep add "$b" "$a"
	[ "$status" -eq 0 ]
	jq -e --arg a "$a" '.[0].dependencies | any(.dependency_type == "blocks" and .id == $a and .status == "closed")' < <(bd show "$b" --readonly --json) >/dev/null
}

@test "note, guarded update, and resolve mutate planning items without promotion" {
	repo=$(make_bd_repo planning_mutations)
	cd "$repo"
	id=$(bd create "old title" --description "old body" --silent)
	printf 'plain note' >note.txt
	run "$CLERK" inbox note "$id" --file note.txt
	[ "$status" -eq 0 ]
	[[ "$(bd show "$id" --readonly --json | jq -r '.[0].notes')" == *"plain note"* ]]
	[ "$(bd show "$id" --readonly --json | jq -r '.[0].status')" = open ]

	guard=$("$CLERK" inbox show "$id" --json | jq -r .body_guard)
	run bash -c 'printf "new body" | "$1" inbox update "$2" --title "new title" --type bug --stdin --body-guard "$3"' _ "$CLERK" "$id" "$guard"
	[ "$status" -eq 0 ]
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].title' <<<"$json")" = "new title" ]
	[ "$(jq -r '.[0].issue_type' <<<"$json")" = bug ]
	[ "$(jq -r '.[0].description' <<<"$json")" = "new body" ]

	run bash -c 'printf "stale body" | "$1" inbox update "$2" --stdin --body-guard "$3"' _ "$CLERK" "$id" "$guard"
	[ "$status" -eq 2 ]
	[[ "$output" == *"stale body guard"* ]]

	run bash -c 'printf "resolution" | "$1" inbox resolve "$2"' _ "$CLERK" "$id"
	[ "$status" -eq 0 ]
	json=$(bd show "$id" --readonly --json)
	[ "$(jq -r '.[0].status' <<<"$json")" = closed ]
	[ "$(jq -r '.[0].close_reason' <<<"$json")" = resolved ]
	[[ "$(jq -r '.[0].notes' <<<"$json")" == *"clerk-resolution:"* ]]
}

@test "inbox ready refuses open blockers and open children but allows a parented unblocked leaf" {
	repo=$(make_bd_repo ready_graph)
	cd "$repo"
	parent=$(bd create "parent" --acceptance "parent ac" --silent)
	blocker=$(bd create "blocker" --parent "$parent" --silent)
	leaf=$(bd create "leaf" --parent "$parent" --acceptance "leaf ac" --silent)
	bd dep add "$leaf" "$blocker" >/dev/null

	run "$CLERK" inbox ready "$parent"
	[ "$status" -eq 2 ]
	[[ "$output" == *"open children"* ]]

	run "$CLERK" inbox ready "$leaf"
	[ "$status" -eq 2 ]
	[[ "$output" == *"open blockers"* ]]

	bd close "$blocker" --reason done >/dev/null
	run "$CLERK" inbox ready "$leaf"
	[ "$status" -eq 0 ]
	[ "$(bd show "$leaf" --readonly --json | jq -r '.[0].labels | index("stage:ready")')" != null ]
}
