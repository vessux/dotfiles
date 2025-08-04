#!/bin/bash

# Generate command guard script from catalog and selections

set -euo pipefail

CATALOG_FILE="$1"
SELECTED_GUARDS="$2"
OUTPUT_FILE="$3"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed" >&2
    exit 1
fi

# Parse selected guards
IFS=',' read -ra GUARDS <<< "$SELECTED_GUARDS"

# Start generating the script
cat > "$OUTPUT_FILE" << 'EOF'
#!/bin/bash

# Claude Code Command Guard
# Generated from guards catalog - DO NOT EDIT DIRECTLY
# To modify, update the catalog and regenerate

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for JSON parsing in hooks" >&2
    exit 1
fi

# Guard rules array
declare -a GUARD_RULES=(
EOF

# Process each selected guard
for guard in "${GUARDS[@]}"; do
    guard=$(echo "$guard" | xargs)  # trim whitespace
    [ -z "$guard" ] && continue
    
    # Check if guard exists
    if ! yq -r ".guards.$guard" "$CATALOG_FILE" | grep -qv "null"; then
        echo "Warning: Guard '$guard' not found in catalog" >&2
        continue
    fi
    
    # Process patterns array (all guards now use patterns only)
    patterns_count=$(yq -r ".guards.$guard.patterns | length // 0" "$CATALOG_FILE")
    if [ "$patterns_count" -gt 0 ]; then
        # Get callback for this guard (applies to all patterns)
        callback=$(yq -r ".guards.$guard.callback // \"none\"" "$CATALOG_FILE")
        
        # Add each pattern with the same callback
        for i in $(seq 0 $((patterns_count - 1))); do
            pattern=$(yq -r ".guards.$guard.patterns[$i]" "$CATALOG_FILE")
            echo "    \"${pattern}|${callback}|${guard}\"" >> "$OUTPUT_FILE"
        done
    else
        echo "Warning: Guard '$guard' has no patterns defined" >&2
    fi
done

# Close the rules array
echo ")" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Add callback functions
cat >> "$OUTPUT_FILE" << 'EOF'
# Callback functions
check_protected_branch() {
    local command="$1"
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    case "$current_branch" in
        "main"|"master"|"production")
            return 1  # Block on protected branches
            ;;
        *)
            return 0  # Allow on feature branches
            ;;
    esac
}

check_dangerous_rm() {
    # Always block rm -rf (too dangerous)
    return 1
}

check_chmod_safety() {
    local command="$1"
    # Block chmod -R 777 (too permissive)
    if [[ "$command" =~ 777 ]]; then
        return 1
    fi
    return 0
}

# Error messages
show_error_message() {
    local guard_id="$1"
    local command="$2"
    
    case "$guard_id" in
EOF

# Add error messages for each guard
for guard in "${GUARDS[@]}"; do
    guard=$(echo "$guard" | xargs)
    [ -z "$guard" ] && continue
    
    # Skip if guard doesn't exist
    if ! yq -r ".guards.$guard" "$CATALOG_FILE" | grep -qv "null"; then
        continue
    fi
    
    echo "        \"$guard\")" >> "$OUTPUT_FILE"
    echo "            cat >&2 << 'MESSAGE_EOF'" >> "$OUTPUT_FILE"
    
    # Extract message from catalog using yq
    message=$(yq -r ".guards.$guard.message // \"Command blocked by $guard guard\"" "$CATALOG_FILE")
    echo "$message" >> "$OUTPUT_FILE"
    
    echo "" >> "$OUTPUT_FILE"
    echo "Blocked command: \$command" >> "$OUTPUT_FILE"
    echo "MESSAGE_EOF" >> "$OUTPUT_FILE"
    echo "            ;;" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

# Complete the script
cat >> "$OUTPUT_FILE" << 'EOF'
        *)
            echo "Command blocked by guard: $guard_id" >&2
            echo "Command: $command" >&2
            ;;
    esac
}

# Main guard logic
main() {
    # Read JSON from stdin
    local json_input=$(cat)
    
    # Extract tool name and command from JSON
    local tool_name=$(echo "$json_input" | jq -r '.tool_name // ""' 2>/dev/null)
    local command=$(echo "$json_input" | jq -r '.tool_input.command // ""' 2>/dev/null)
    
    # Only process Bash tool calls
    if [ "$tool_name" != "Bash" ]; then
        exit 0
    fi
    
    # Exit if no command found
    [ -z "$command" ] && exit 0
    
    # Check each guard rule
    for rule in "${GUARD_RULES[@]}"; do
        IFS='|' read -r pattern callback message_key <<< "$rule"
        
        # Check if command matches pattern
        case "$command" in
            $pattern)
                # Run callback if specified
                if [ "$callback" != "none" ] && command -v "$callback" >/dev/null 2>&1; then
                    if ! "$callback" "$command"; then
                        show_error_message "$message_key" "$command"
                        exit 2  # Blocking error
                    fi
                else
                    # No callback or pattern match - block immediately
                    if [ "$callback" = "none" ]; then
                        show_error_message "$message_key" "$command"
                        exit 2  # Blocking error
                    fi
                fi
                ;;
        esac
    done
    
    exit 0
}

main
EOF

chmod +x "$OUTPUT_FILE"

echo "Generated command guard script at: $OUTPUT_FILE"
echo "Guards enabled: $SELECTED_GUARDS"