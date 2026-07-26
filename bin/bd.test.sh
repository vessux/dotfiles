#!/usr/bin/env bash
# bin/bd.test.sh — hermetic tests for the bin/bd shim's shared-server bootstrap fix
# (dotfiles-<TBD>). Follows the ccstatusline/umbel-segment.test.sh convention: a standalone,
# non-bats companion script next to the file it tests (exit 0 = all pass), NOT currently wired
# into clerk/project-gate (which only runs `bats tests/clerk` — see that file's `bats
# tests/clerk && shellcheck -S error bin/*`). Run directly: ./bin/bd.test.sh
#
# Two layers, matching the two halves of the fix:
#   1. Direct unit tests of the two new helper functions, via SOURCING bin/bd — exactly what
#      the `[ "${BASH_SOURCE[0]}" = "${0}" ]` guard at the bottom of bin/bd exists for: sourcing
#      exposes the functions without running _bd_shim_main.
#   2. An end-to-end behavioural test of `bd bootstrap --dry-run` through the shim as an
#      EXECUTED script (this is the only way to exercise _bd_shim_main itself), with BD_REAL_BIN
#      pointed at a stub "real bd" that just echoes back the argv and env it received — no real
#      bd/dolt/network involved, so this stays hermetic and can never touch a live database.
set -u

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUT="$DIR/bd"

fails=0
check() {
	desc=$1; expected=$2; actual=$3
	if [ "$actual" = "$expected" ]; then
		printf 'ok   - %s\n' "$desc"
	else
		printf 'FAIL - %s\n       expected: [%s]\n       actual:   [%s]\n' \
			"$desc" "$(printf '%s' "$expected" | cat -v)" "$(printf '%s' "$actual" | cat -v)"
		fails=$((fails + 1))
	fi
}

# ---------------------------------------------------------------------------
# Layer 1: source the shim, call the two new helpers directly.
# ---------------------------------------------------------------------------
# shellcheck source=bd
. "$SUT"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- _bd_shim_is_shared_server_host ---

# No ~/.beads/shared-server/ at all (the Mac's shape) -> false.
HOME="$work/mac-home"
mkdir -p "$HOME"
if _bd_shim_is_shared_server_host; then res=yes; else res=no; fi
check "no shared-server dir at all -> not a shared-server host" "no" "$res"

# ~/.beads/shared-server/ exists but the config file doesn't (e.g. mid-decommission) -> false.
HOME="$work/half-provisioned-home"
mkdir -p "$HOME/.beads/shared-server/dolt/somedb"
if _bd_shim_is_shared_server_host; then res=yes; else res=no; fi
check "shared-server data dir present without beads-server.yaml -> not a shared-server host" "no" "$res"

# The actual marker file present (devbox's shape) -> true.
HOME="$work/devbox-home"
mkdir -p "$HOME/.beads/shared-server"
: > "$HOME/.beads/shared-server/beads-server.yaml"
if _bd_shim_is_shared_server_host; then res=yes; else res=no; fi
check "beads-server.yaml present -> is a shared-server host" "yes" "$res"

# --- _read_config_database ---

mkdir -p "$work/proj-ok/.beads"
cat > "$work/proj-ok/.beads/config.yaml" <<'EOF'
# comment mentioning dolt.database: "not-this-one" must not be picked up
sync.remote: "git+https://github.com/vessux/tuidriver.git"
dolt.database: "tuidriver"
EOF
_BD_BEADS_DIR="$work/proj-ok/.beads"
if _read_config_database; then res="ok:$_BD_CFG_DB"; else res="fail:$_BD_CFG_DB"; fi
check "flat dolt.database key, ignores a commented-out mention -> parses the real value" "ok:tuidriver" "$res"

mkdir -p "$work/proj-missing/.beads"
cat > "$work/proj-missing/.beads/config.yaml" <<'EOF'
sync.remote: "git+https://github.com/vessux/tuidriver.git"
# dolt.database: "tuidriver"   (commented out, never added — the honest-error case)
EOF
_BD_BEADS_DIR="$work/proj-missing/.beads"
if _read_config_database; then res="ok:$_BD_CFG_DB"; else res="fail:$_BD_CFG_DB"; fi
check "dolt.database key only in a comment -> treated as absent" "fail:" "$res"

# ---------------------------------------------------------------------------
# Layer 2: execute the shim end-to-end against a stub "real bd", proving the actual bootstrap
# invocation gets (or doesn't get) the two env vars — the thing that was silently wrong before.
# ---------------------------------------------------------------------------
stub="$work/stub-bd"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
printf 'ARGV:%s\n' "$*"
printf 'SHARED:%s\n' "${BEADS_DOLT_SHARED_SERVER:-<unset>}"
printf 'DATABASE:%s\n' "${BEADS_DOLT_SERVER_DATABASE:-<unset>}"
EOF
chmod +x "$stub"

fresh_clone="$work/fresh-clone/.beads"
mkdir -p "$fresh_clone"
cat > "$fresh_clone/config.yaml" <<'EOF'
sync.remote: "git+https://github.com/vessux/tuidriver.git"
dolt.database: "tuidriver"
EOF
# Deliberately no metadata.json: this IS the fresh-clone shape (config.yaml tracked,
# metadata.json gitignored and absent until a real bootstrap runs).

# devbox-shaped host: shared-server marker present -> shim must supply both vars.
devbox_home="$work/devbox-home2"
mkdir -p "$devbox_home/.beads/shared-server"
: > "$devbox_home/.beads/shared-server/beads-server.yaml"

out=$(HOME="$devbox_home" BEADS_DIR="$fresh_clone" BD_REAL_BIN="$stub" bash "$SUT" bootstrap --dry-run)
check "shared-server host: SHARED is exported" "SHARED:1" "$(printf '%s\n' "$out" | grep '^SHARED:')"
check "shared-server host: DATABASE derived from config.yaml" "DATABASE:tuidriver" "$(printf '%s\n' "$out" | grep '^DATABASE:')"

# Mac-shaped host: no shared-server marker anywhere -> behaviour unchanged (neither var set,
# same as before this fix existed).
mac_home="$work/mac-home2"
mkdir -p "$mac_home"
out=$(HOME="$mac_home" BEADS_DIR="$fresh_clone" BD_REAL_BIN="$stub" bash "$SUT" bootstrap --dry-run)
check "non-shared-server host (the Mac): SHARED left unset" "SHARED:<unset>" "$(printf '%s\n' "$out" | grep '^SHARED:')"
check "non-shared-server host (the Mac): DATABASE left unset" "DATABASE:<unset>" "$(printf '%s\n' "$out" | grep '^DATABASE:')"

# Shared-server host but config.yaml has no dolt.database key -> loud error, not a guessed name.
fresh_clone_nokey="$work/fresh-clone-nokey/.beads"
mkdir -p "$fresh_clone_nokey"
cat > "$fresh_clone_nokey/config.yaml" <<'EOF'
sync.remote: "git+https://github.com/vessux/example.git"
EOF
err=$(HOME="$devbox_home" BEADS_DIR="$fresh_clone_nokey" BD_REAL_BIN="$stub" bash "$SUT" bootstrap --dry-run 2>&1 >/dev/null)
rc=0
HOME="$devbox_home" BEADS_DIR="$fresh_clone_nokey" BD_REAL_BIN="$stub" bash "$SUT" bootstrap --dry-run >/dev/null 2>/dev/null || rc=$?
check "missing dolt.database key -> exits 69 (not a guess)" "69" "$rc"
check "missing dolt.database key -> stderr names the fix" "yes" "$(printf '%s' "$err" | grep -q 'dolt.database' && echo yes || echo no)"

# A caller who already set one of the two vars is left alone (explicit override wins).
out=$(HOME="$devbox_home" BEADS_DIR="$fresh_clone" BD_REAL_BIN="$stub" BEADS_DOLT_SERVER_DATABASE=explicit-choice bash "$SUT" bootstrap --dry-run)
check "caller already set BEADS_DOLT_SERVER_DATABASE: shim does not also set SHARED" "SHARED:<unset>" "$(printf '%s\n' "$out" | grep '^SHARED:')"
check "caller already set BEADS_DOLT_SERVER_DATABASE: shim leaves the caller's value alone" "DATABASE:explicit-choice" "$(printf '%s\n' "$out" | grep '^DATABASE:')"

echo
if [ "$fails" -eq 0 ]; then
	echo "All tests passed."
	exit 0
fi
echo "$fails test(s) failed."
exit 1
