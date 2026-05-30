#!/usr/bin/env bash
# latest-conversation.sh — review the previous completed assistant turn in revdiff.
#
# extracts the assistant text bounded by the last two typed-user prompts from
# the active Claude Code session JSONL, opens it in revdiff via the standard
# overlay launcher, and post-processes annotations to inline the referenced
# source lines so the model can act on returned feedback without re-reading
# the temp file.
#
# soft-fails (exit 0 with a stderr message) when the transcript is missing,
# jq is unavailable, or the session has no completed assistant turn yet.

set -euo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude-code}"
PROJ_DIR="$CONFIG_DIR/projects/$(pwd | sed 's|/|-|g')"

if [ ! -d "$PROJ_DIR" ]; then
    echo "no Claude Code transcript directory for $(pwd)" >&2
    exit 0
fi

# prefer the env-supplied session id; fall back to newest *.jsonl by mtime
JSONL=""
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && [ -f "$PROJ_DIR/$CLAUDE_CODE_SESSION_ID.jsonl" ]; then
    JSONL="$PROJ_DIR/$CLAUDE_CODE_SESSION_ID.jsonl"
else
    for f in "$PROJ_DIR"/*.jsonl; do
        [ -e "$f" ] || continue
        if [ -z "$JSONL" ] || [ "$f" -nt "$JSONL" ]; then JSONL="$f"; fi
    done
fi

if [ -z "$JSONL" ] || [ ! -f "$JSONL" ]; then
    echo "no Claude Code session transcript found in $PROJ_DIR" >&2
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found in PATH (required to parse transcript)" >&2
    exit 0
fi

TMPBASE="${TMPDIR:-/tmp}"
TMPFILE=$(mktemp "$TMPBASE/revdiff-latest-XXXXXX.md")
RAW_OUT=$(mktemp "$TMPBASE/revdiff-latest-out-XXXXXX")
trap 'rm -f "$TMPFILE" "$RAW_OUT"' EXIT

# extract all assistant text blocks between the last two typed-user prompts.
# a typed prompt has .type=="user" with .message.content as a string;
# tool_result records are .type=="user" with .message.content as an array, so
# they're excluded as boundaries.
jq -s -r '
  . as $all
  | [range(0; length) | select($all[.].type=="user" and ($all[.].message.content | type) == "string")] as $prompts
  | if ($prompts | length) < 2 then ""
    else
      ($prompts[-2]) as $start
      | ($prompts[-1]) as $end
      | $all[($start+1):$end]
      | map(select(.type=="assistant"))
      | map(.message.content | map(select(.type=="text") | .text))
      | flatten | join("\n\n")
    end
' "$JSONL" > "$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
    echo "no completed assistant turn available yet" >&2
    exit 0
fi

SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LAUNCHER=$("$SKILL_DIR/scripts/resolve-launcher.sh" launch-revdiff.sh "${CLAUDE_PLUGIN_DATA:-}")

# launcher returns 10 when annotations were captured; set +e to keep both 0 and 10 alive
set +e
"$LAUNCHER" --only="$TMPFILE" --description="Reviewing the assistant's previous completed turn (extracted from session transcript)." > "$RAW_OUT"
rc=$?
set -e

if [ "$rc" -ne 0 ] && [ "$rc" -ne 10 ]; then
    echo "revdiff launcher exited with status $rc" >&2
    exit 0
fi

if [ ! -s "$RAW_OUT" ]; then
    exit 0
fi

# post-process: for each `## <name>:<line>[-<end>] (<type>)` header, inject a
# fenced quote of the referenced source lines from the temp file. file-level
# and unrecognized headers pass through verbatim.
awk -v src="$TMPFILE" '
  BEGIN {
    n = 0
    while ((getline line < src) > 0) src_lines[++n] = line
    close(src)
    total = n
  }
  function quote_range(s, e,    i, span) {
    print "```"
    span = e - s + 1
    if (span <= 5) {
      for (i = s; i <= e && i <= total; i++) print src_lines[i]
    } else {
      for (i = s; i <= s + 2 && i <= total; i++) print src_lines[i]
      print "..."
      if (e <= total) print src_lines[e]
    }
    print "```"
  }
  /^## / {
    if (match($0, /:[0-9]+(-[0-9]+)? \(/)) {
      print $0
      colon = index($0, ":")
      after = substr($0, colon + 1)
      sp = index(after, " ")
      range = substr(after, 1, sp - 1)
      s_ln = range + 0
      e_ln = s_ln
      if (index(range, "-") > 0) e_ln = substr(range, index(range, "-") + 1) + 0
      quote_range(s_ln, e_ln)
      next
    }
    print
    next
  }
  { print }
' "$RAW_OUT"
