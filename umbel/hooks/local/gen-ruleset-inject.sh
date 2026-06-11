#!/usr/bin/env bash
# Generate the per-track ruleset inject hooks from one source: _ruleset-inject.template.
#
# discovery-ruleset/inject and delivery-base-ruleset/inject are identical except
# their TRACK= line. umbel ships each leaf dir verbatim, so the copies can't be
# shared at the umbel layer (each must run standalone, citing nothing repo-local);
# instead they are generated from the template here, so a single edit regenerates
# both and they can't silently drift. The template lives outside any leaf dir, so
# umbel never ships it. See umbel/docs/adr/0010-cross-bundle-hook-duplication-generated-not-shared.md
#
#   gen-ruleset-inject.sh            regenerate both inject scripts in place
#   gen-ruleset-inject.sh --check    verify committed injects match the template (exit 1 on drift)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/_ruleset-inject.template"
HEADER="# GENERATED from _ruleset-inject.template by gen-ruleset-inject.sh — do not edit; edit the template and regenerate"

# track -> generated leaf inject (each leaf is shipped verbatim by its own bundle)
TARGETS=(
  "discovery=$SCRIPT_DIR/discovery-ruleset/inject"
  "delivery=$SCRIPT_DIR/delivery-base-ruleset/inject"
)

mode="write"
if [ "$#" -gt 0 ]; then
  case "$1" in
    --check) mode="check" ;;
    -h|--help)
      printf 'usage: %s [--check]\n  (no arg)  regenerate both inject scripts\n  --check   verify committed injects match the template\n' "$0"
      exit 0 ;;
    *) printf 'usage: %s [--check]\n' "$0" >&2; exit 2 ;;
  esac
fi

# Render the template for one track: keep the shebang on line 1, drop the GENERATED
# header in right after it, and stamp TRACK wherever the @TRACK@ placeholder appears.
render() {
  awk -v track="$1" -v hdr="$HEADER" '
    NR == 1 { print; print hdr; next }
    { gsub(/@TRACK@/, track); print }
  ' "$TEMPLATE"
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

drift=0
for entry in "${TARGETS[@]}"; do
  track="${entry%%=*}"
  target="${entry#*=}"
  render "$track" > "$tmp"
  if [ "$mode" = check ]; then
    if cmp -s "$target" "$tmp"; then
      printf 'ok: %s\n' "$target"
    else
      printf 'DRIFT: %s differs from the template\n' "$target" >&2
      drift=1
    fi
  else
    cp "$tmp" "$target"
    chmod +x "$target"
    printf 'wrote %s\n' "$target"
  fi
done

if [ "$mode" = check ] && [ "$drift" -ne 0 ]; then
  printf 'Committed injects are stale. Run: %s   then commit.\n' "$0" >&2
  exit 1
fi
