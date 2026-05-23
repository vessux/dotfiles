#!/bin/bash
# Publishes Claude Code hook events to an ntfy.sh topic.
# The Mac subscriber (claude-code/scripts/notify-subscriber.sh, run via launchd)
# is what turns these into popups + voice. On devbox the publisher fires; the
# subscriber on the Mac picks it up and notifies there.

WEBHOOK_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/notify-webhook.url"
[[ -f "$WEBHOOK_FILE" ]] || exit 0

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

case "$EVENT" in
  Stop)              PHRASE="$PROJECT ready" ;;
  PermissionRequest) PHRASE="$PROJECT permission" ;;
  *)                 exit 0 ;;
esac

curl -fsS -m 5 -d "$PHRASE" "$(cat "$WEBHOOK_FILE")" >/dev/null 2>&1 &
disown

exit 0
