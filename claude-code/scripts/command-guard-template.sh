#!/bin/bash

# Claude Code Hook: Command Guard System Template
# 
# Flexible command blocking system with configurable matchers and callbacks.
# Template for creating project-specific command guards.
#
# Usage: Copy this template and customize the GUARD_RULES array

# TEMPLATE CONFIGURATION
# ======================
# 
# Each rule has the format: "pattern|callback_function|error_message_key"
# 
# pattern: Shell glob pattern to match against commands
# callback_function: Function name to call for additional validation (optional: use "none" to skip)
# error_message_key: Key for the error message (defined in show_error_message function)

declare -a GUARD_RULES=(
    # Example rules (customize these):
    # "pattern|callback|message_key"
    "*chatui-tui*|none|tui_blocked"
    "*poetry run chatui*|none|tui_blocked" 
    "*git*--no-verify*|check_git_branch|no_verify_blocked"
    "*rm -rf*|check_dangerous_rm|dangerous_rm_blocked"
)

# CALLBACK FUNCTIONS
# ==================
# Add custom validation logic here. Return 0 to allow, non-zero to block.

check_git_branch() {
    local command="$1"
    # Allow --no-verify on main branch, block on feature branches
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    case "$current_branch" in
        "main"|"master")
            return 0  # Allow on main/master
            ;;
        *)
            return 1  # Block on feature branches
            ;;
    esac
}

check_dangerous_rm() {
    local command="$1"
    # Block any rm -rf commands (too dangerous)
    return 1
}

# ERROR MESSAGE SYSTEM
# ====================
# Centralized error messages for consistency

show_error_message() {
    local message_key="$1"
    local command="$2"
    
    case "$message_key" in
        "tui_blocked")
            cat >&2 << 'EOF'
🚫 TUI Command Blocked!

❌ NEVER run TUI applications directly - causes terminal poisoning
✅ Use Pilot testing framework instead:

```python
import asyncio
from chatui.tui.app import ChatUIApp
from chatui.core.container import get_container

async def test_tui():
    container = get_container()
    app = ChatUIApp(container=container)
    async with app.run_test(size=(120, 40)) as pilot:
        pilot.app.save_screenshot("debug/screenshots/test.svg")

asyncio.run(test_tui())
```

Run: poetry run python debug/test_script.py
EOF
            ;;
        "no_verify_blocked")
            cat >&2 << EOF
🚫 Git --no-verify Blocked on Feature Branch!

❌ --no-verify bypasses quality gates on feature branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)
✅ Run quality checks first or switch to main branch

Allowed:
- git commit (without --no-verify) - runs all hooks
- Switch to main: git checkout main

Blocked command: $command
EOF
            ;;
        "dangerous_rm_blocked")
            cat >&2 << EOF
🚫 Dangerous rm -rf Command Blocked!

❌ rm -rf is extremely dangerous and can cause data loss
✅ Use specific file paths or safer alternatives

Safer alternatives:
- rm specific_file.txt
- git clean -fd (for git repos)
- trash command (if available)

Blocked command: $command
EOF
            ;;
        *)
            cat >&2 << EOF
🚫 Command Blocked by Guard

Command: $command
Reason: Custom guard rule triggered
EOF
            ;;
    esac
}

# MAIN GUARD LOGIC
# ================
# Fast pattern matching with callback support

main() {
    local command="${CLAUDE_COMMAND:-$*}"
    
    # Quick exit if no command
    [ -z "$command" ] && exit 0
    
    # Check each guard rule
    for rule in "${GUARD_RULES[@]}"; do
        # Parse rule: pattern|callback|message_key
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
                    show_error_message "$message_key" "$command"
                    exit 2  # Blocking error
                fi
                ;;
        esac
    done
    
    # No rules matched - allow command
    exit 0
}

# Execute main function
main "$@"