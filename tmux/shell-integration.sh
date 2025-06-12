# Tmux Shell Integration
# Add this to your ~/.zshrc or ~/.bashrc

# Smart tmux function - always attach to existing sessions
tmux() {
    # If no arguments provided, use smart attach behavior
    if [[ $# -eq 0 ]]; then
        # Check if any sessions exist
        if command tmux list-sessions >/dev/null 2>&1; then
            echo "🔗 Attaching to existing session..."
            command tmux attach-session
        else
            echo "🚀 Starting tmux (resurrection will handle session creation)..."
            command tmux
        fi
    else
        # Pass through all arguments to tmux
        command tmux "$@"
    fi
}

# Convenient aliases
alias tm='tmux'                                    # Short alias
alias tml='tmux list-sessions'                     # List sessions
alias tmka='tmux kill-server'                      # Kill all sessions

# Nuclear option - kill everything and prevent resurrection
tmnuke() {
    echo "💀 Nuclear option: Killing all sessions and wiping save history..."
    
    # Kill all tmux sessions
    tmux kill-server 2>/dev/null || true
    
    # Delete all save files but leave minimal structure for resurrection system
    local resurrect_dir="$HOME/.local/share/tmux/resurrect"
    if [[ -d "$resurrect_dir" ]]; then
        echo "🗑️  Deleting all save files..."
        rm -rf "$resurrect_dir"
    fi
    
    echo "🧹 All tmux data nuked - fresh start guaranteed!"
}

# Smart session selector with fzf (if available)
tms() {
    if command -v fzf >/dev/null 2>&1; then
        local session
        session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | fzf --prompt="Select session: " --height=10 --border)
        if [[ -n "$session" ]]; then
            tmux attach-session -t "$session"
        fi
    else
        echo "📋 Available sessions:"
        tmux list-sessions 2>/dev/null || echo "No sessions found"
    fi
}

# Interactive session killer with fzf (if available)
tmkill() {
    if command -v fzf >/dev/null 2>&1; then
        local sessions
        sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
        
        if [[ -z "$sessions" ]]; then
            echo "❌ No sessions to kill"
            return 1
        fi
        
        local session
        session=$(echo "$sessions" | fzf --prompt="Kill session: " --height=10 --border)
        if [[ -n "$session" ]]; then
            echo "💀 Killing session '$session'..."
            tmux kill-session -t "$session"
            echo "✅ Session '$session' killed"
        fi
    else
        echo "📋 Available sessions to kill:"
        tmux list-sessions 2>/dev/null || echo "No sessions found"
        echo "💡 Install fzf for interactive selection"
    fi
}

# Create or attach to project session (uses current directory name)
tmp() {
    local session_name
    session_name=$(basename "$(pwd)" | tr '.' '_')
    
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "🔗 Attaching to project session '$session_name'..."
        tmux attach-session -t "$session_name"
    else
        echo "🚀 Creating project session '$session_name'..."
        tmux new-session -s "$session_name"
    fi
}