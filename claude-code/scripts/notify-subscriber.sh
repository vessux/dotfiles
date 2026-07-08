#!/bin/bash
# Subscribes to the ntfy.sh topic published by hooks/notify.sh and renders
# popup + voice on the Mac. Run via launchd (see launchd/dev.kovis.claude-
# notify-subscriber.plist). Mac-only — needs terminal-notifier and `say`.
#
# Voice is gated by the presence of ~/.config/claude-code/notify-silent
# (toggled via the mute-claude / unmute-claude aliases in zsh/.zshrc).
# Popup always fires.

set -u

WEBHOOK_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/notify-webhook.url"
SILENT_FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/notify-silent"

if [[ ! -f "$WEBHOOK_FILE" ]]; then
  echo "notify-subscriber: no webhook URL at $WEBHOOK_FILE" >&2
  exit 1
fi

PUBLISH_URL=$(cat "$WEBHOOK_FILE")
SUB_URL="${PUBLISH_URL%/}/json"

# ntfy.sh streams one JSON object per line over a long-lived HTTP connection.
# --retry keeps reconnecting if the connection drops.
exec curl -sS -N --retry 999999 --retry-delay 5 "$SUB_URL" | while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  message=$(echo "$line" | jq -r 'select(.event == "message") | .message // empty')
  [[ -z "$message" ]] && continue

  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier \
      -title "Coding agent" \
      -message "$message" \
      -activate "com.mitchellh.ghostty" \
      >/dev/null 2>&1
  fi

  if [[ ! -f "$SILENT_FLAG" ]] && command -v say >/dev/null 2>&1; then
    say -v Zarvox "Agent: $message"
  fi
done
