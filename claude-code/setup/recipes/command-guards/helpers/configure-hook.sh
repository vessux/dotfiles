#!/bin/bash

# configure-hook.sh - Configure Claude Code hooks in settings.json
# Usage: ./configure-hook.sh <hook_script_path> <settings_file_path>

set -e

HOOK_SCRIPT="$1"
SETTINGS_FILE="$2"

if [ -z "$HOOK_SCRIPT" ] || [ -z "$SETTINGS_FILE" ]; then
    echo "Usage: $0 <hook_script_path> <settings_file_path>"
    exit 1
fi

# Ensure directory exists
mkdir -p "$(dirname "$SETTINGS_FILE")"

# Create or update settings.json with proper hook structure
if [ -f "$SETTINGS_FILE" ]; then
    # Check if this hook already exists
    if jq --arg script "$HOOK_SCRIPT" '
        .hooks.PreToolUse // [] | 
        map(select(.matcher == "Bash")) | 
        map(.hooks[]) | 
        map(select(.command == $script)) | 
        length > 0
    ' "$SETTINGS_FILE" | grep -q true; then
        echo "⚠️  Hook already configured: $HOOK_SCRIPT"
        exit 0
    fi
    
    # Update existing file - append to hooks array
    jq --arg script "$HOOK_SCRIPT" '
        # Initialize hooks object if it doesn'\''t exist
        .hooks = (.hooks // {}) |
        # Initialize PreToolUse array if it doesn'\''t exist
        .hooks.PreToolUse = (.hooks.PreToolUse // []) |
        # Find existing Bash matcher or create new entry
        if (.hooks.PreToolUse | map(.matcher == "Bash") | any) then
            # Append to existing Bash matcher hooks
            .hooks.PreToolUse = (.hooks.PreToolUse | map(
                if .matcher == "Bash" then
                    .hooks += [{
                        "type": "command",
                        "command": $script
                    }]
                else
                    .
                end
            ))
        else
            # Add new Bash matcher entry
            .hooks.PreToolUse += [{
                "matcher": "Bash",
                "hooks": [{
                    "type": "command",
                    "command": $script
                }]
            }]
        end
    ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
else
    # Create new file
    jq -n --arg script "$HOOK_SCRIPT" '{
        "hooks": {
            "PreToolUse": [{
                "matcher": "Bash",
                "hooks": [{
                    "type": "command",
                    "command": $script
                }]
            }]
        }
    }' > "$SETTINGS_FILE"
fi

echo "✅ Configured hook in $SETTINGS_FILE"