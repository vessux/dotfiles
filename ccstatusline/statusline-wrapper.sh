#!/bin/bash
# Wrapper that optionally logs Claude Code's status JSON, then forwards to
# ccstatusline. Logging is enabled by pre-creating the log directory:
#
#   mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/claude-statusline-logs"
#
# When the directory is absent the wrapper just passes through with no log
# write. This is how devbox skips analytics while Mac keeps them.

INPUT=$(cat)

LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-statusline-logs"
if [[ -d "$LOG_DIR" ]]; then
    echo "$INPUT" >> "$LOG_DIR/$(date +%Y-%m-%d).jsonl"
fi

echo "$INPUT" | npx -y ccstatusline@latest
