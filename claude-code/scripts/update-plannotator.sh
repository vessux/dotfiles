#!/usr/bin/env bash
# Update the plannotator binary only — skip the upstream installer's
# skill/plugin side-effects (commands, agents, hooks, sparse-checkout, ...).
#
# Upstream installer: https://plannotator.ai/install.sh
# Releases:           https://github.com/backnotprop/plannotator/releases
#
# Usage:
#   update-plannotator.sh            # install latest
#   update-plannotator.sh v0.19.21   # pin a tag
#   update-plannotator.sh --force    # reinstall even if already current

set -euo pipefail

REPO="backnotprop/plannotator"
INSTALL_DIR="${PLANNOTATOR_INSTALL_DIR:-$HOME/.local/bin}"
BIN_PATH="$INSTALL_DIR/plannotator"

force=0
tag=""
for arg in "$@"; do
    case "$arg" in
        --force|-f) force=1 ;;
        v*)         tag="$arg" ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

detect_target() {
    local os arch
    case "$(uname -s)" in
        Darwin) os=darwin ;;
        Linux)  os=linux ;;
        *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch=arm64 ;;
        x86_64|amd64)  arch=amd64 ;;
        *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
    esac
    echo "${os}-${arch}"
}

target=$(detect_target)

if [[ -z "$tag" ]]; then
    tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1)
    if [[ -z "$tag" ]]; then
        echo "could not resolve latest release tag" >&2
        exit 1
    fi
fi

current=""
if [[ -x "$BIN_PATH" ]]; then
    current=$("$BIN_PATH" --version 2>/dev/null | awk '{print $2}' || true)
fi
want="${tag#v}"

if [[ "$force" -eq 0 && -n "$current" && "$current" == "$want" ]]; then
    echo "plannotator $current already current ($tag) — pass --force to reinstall"
    exit 0
fi

echo "updating plannotator: ${current:-none} -> $want ($target)"

base="https://github.com/${REPO}/releases/download/${tag}"
asset="plannotator-${target}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/plannotator" "$base/$asset"
curl -fsSL --retry 3 -o "$tmp/plannotator.sha256" "$base/${asset}.sha256"

expected=$(awk '{print $1}' "$tmp/plannotator.sha256")
actual=$(shasum -a 256 "$tmp/plannotator" | awk '{print $1}')
if [[ "$expected" != "$actual" ]]; then
    echo "sha256 mismatch:" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
fi

chmod +x "$tmp/plannotator"

# macOS quarantine attribute would block exec from a non-Apple binary.
if command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$tmp/plannotator" 2>/dev/null || true
fi

mkdir -p "$INSTALL_DIR"
mv -f "$tmp/plannotator" "$BIN_PATH"

installed=$("$BIN_PATH" --version 2>&1 | awk '{print $2}')
echo "plannotator $installed installed at $BIN_PATH"
