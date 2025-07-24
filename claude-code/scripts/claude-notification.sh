#!/bin/bash

# Enhanced notification script for Claude Code
# Triggers when Claude finishes and waits for user input
# Includes clickable notifications that focus the correct Ghostty/tmux window

# Get current terminal session information
GHOSTTY_WINDOW_ID="${GHOSTTY_WINDOW_ID:-}"
TMUX_PANE="${TMUX_PANE:-}"
# Extract session name from tmux if we're in a tmux session
if [[ -n "$TMUX" ]]; then
    TMUX_SESSION=$(tmux display-message -p "#{session_name}" 2>/dev/null || echo "")
    # Get the window and pane index for proper focusing
    TMUX_WINDOW=$(tmux display-message -p "#{window_index}" 2>/dev/null || echo "")
    TMUX_PANE_INDEX=$(tmux display-message -p "#{pane_index}" 2>/dev/null || echo "")
else
    TMUX_SESSION=""
    TMUX_WINDOW=""
    TMUX_PANE_INDEX=""
fi
PWD_INFO="$(pwd)"


if command -v terminal-notifier >/dev/null 2>&1; then
    # macOS: Use terminal-notifier with clickable notification
    terminal-notifier -title "Claude Code" \
                     -message "Claude is waiting for your input (Session: ${TMUX_SESSION}, Window: ${TMUX_WINDOW}, Pane: ${TMUX_PANE_INDEX})" \
                     -sound "Glass" \
                     -execute "osascript -e 'tell application \"Ghostty\" to activate'" \
                     -timeout 30

elif command -v notify-send >/dev/null 2>&1; then
    # Linux notification with action
    # Linux: Just focus terminal (tmux switching is complex with notifications)
    focus_cmd="echo 'Focus terminal manually'"
    
    notify-send "Claude Code" "Claude is waiting for your input" \
        --icon=terminal \
        --urgency=normal \
        --expire-time=30000 \
        --action="focus=Focus Terminal" \
        --hint=string:x-canonical-private-synchronous:claude

elif command -v powershell.exe >/dev/null 2>&1; then
    # Windows (WSL) notification
    powershell.exe -Command "New-BurntToastNotification -Text 'Claude Code', 'Claude is waiting for your input (Session: ${TMUX_SESSION})'"
else
    # Fallback: terminal bell and visual indicator
    echo -e "\a"
    echo "🔔 Claude Code is waiting for your input"
    echo "📍 Session: ${TMUX_SESSION:-none} | Pane: ${TMUX_PANE:-none}"
    echo "📂 Directory: ${PWD_INFO}"
fi