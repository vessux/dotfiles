#!/usr/bin/env bash

# Tmux Setup & Installation Script
# Comprehensive setup for tmux with Catppuccin theme and plugins

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Emoji for better UX
ROCKET="🚀"
CHECK="✅"
CROSS="❌"
INFO="ℹ️"
WARN="⚠️"

print_header() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   🎯 TMUX SETUP WIZARD 🎯                    ║"
    echo "║            Catppuccin Theme + Awesome Plugins               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}${ROCKET} $1${NC}"
}

print_success() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

print_error() {
    echo -e "${RED}${CROSS} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${WARN} $1${NC}"
}

print_info() {
    echo -e "${CYAN}${INFO} $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
check_dependencies() {
    print_step "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command_exists tmux; then
        missing_deps+=(tmux)
    fi
    
    if ! command_exists stow; then
        missing_deps+=(stow)
    fi
    
    if ! command_exists git; then
        missing_deps+=(git)
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Please install missing dependencies and run again"
        exit 1
    fi
    
    print_success "All dependencies found"
}

# Check if we're in the right directory
check_location() {
    print_step "Checking location..."
    
    if [[ ! -f "../.stowrc" ]] || [[ ! -d "../tmux" ]]; then
        print_error "Script must be run from ~/dotfiles/tmux/ directory"
        print_info "Current directory: $(pwd)"
        exit 1
    fi
    
    print_success "Location verified: $(pwd)"
}

# Stow dotfiles
stow_dotfiles() {
    print_step "Stowing dotfiles..."
    
    cd ..  # Go to dotfiles root
    
    if stow . 2>/dev/null; then
        print_success "Dotfiles stowed successfully"
    else
        print_warning "Stow may have conflicts, but continuing..."
    fi
    
    cd tmux  # Return to tmux directory
}

# Install TPM
install_tpm() {
    print_step "Installing TPM (Tmux Plugin Manager)..."
    
    local tpm_dir="$HOME/.config/tmux/plugins/tpm"
    
    if [[ -d "$tpm_dir" ]]; then
        print_warning "TPM already exists, updating..."
        cd "$tpm_dir" && git pull origin master >/dev/null 2>&1
        print_success "TPM updated"
    else
        print_info "Cloning TPM repository..."
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir" >/dev/null 2>&1
        print_success "TPM installed to $tpm_dir"
    fi
}

# Install additional dependencies
install_fzf() {
    print_step "Checking for fzf (required for tmux-fzf plugin)..."
    
    if command_exists fzf; then
        print_success "fzf found"
    else
        print_warning "fzf not found - some fuzzy finder features may not work"
        print_info "Install with: brew install fzf"
    fi
}

# Start tmux and install plugins
install_plugins() {
    print_step "Installing tmux plugins..."
    
    # Check if tmux is running
    if tmux list-sessions >/dev/null 2>&1; then
        print_info "Tmux is running, installing plugins in existing session..."
        tmux run-shell '~/.config/tmux/plugins/tpm/bin/install_plugins'
    else
        print_info "Starting tmux and installing plugins..."
        # Start tmux in detached session, install plugins, then kill session
        tmux new-session -d -s "plugin-install" \; \
             run-shell '~/.config/tmux/plugins/tpm/bin/install_plugins' \; \
             kill-session -t "plugin-install" 2>/dev/null || true
    fi
    
    print_success "Plugins installed"
}

# Create a nice startup session
create_startup_session() {
    print_step "Creating startup session 'main'..."
    
    if tmux has-session -t main 2>/dev/null; then
        print_warning "Session 'main' already exists, skipping..."
        return
    fi
    
    # Create session with multiple windows
    tmux new-session -d -s main -n "terminal"
    tmux new-window -t main -n "editor"
    tmux new-window -t main -n "monitor"
    
    # Setup monitor window with splits
    tmux send-keys -t main:monitor "htop" C-m
    tmux split-window -h -t main:monitor
    tmux send-keys -t main:monitor.1 "echo 'Welcome to your tmux setup!' && echo 'Use Alt+tap for prefix commands'" C-m
    
    # Go back to terminal window
    tmux select-window -t main:terminal
    
    print_success "Startup session 'main' created"
}

# Validate installation
validate_installation() {
    print_step "Validating installation..."
    
    local config_file="$HOME/.config/tmux/tmux.conf"
    local tpm_dir="$HOME/.config/tmux/plugins/tpm"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Config file not found at $config_file"
        return 1
    fi
    
    if [[ ! -d "$tpm_dir" ]]; then
        print_error "TPM not found at $tpm_dir"
        return 1
    fi
    
    # Check if some plugins are installed
    local plugin_count=$(find "$HOME/.config/tmux/plugins" -maxdepth 1 -type d | wc -l)
    if [[ $plugin_count -lt 3 ]]; then
        print_warning "Fewer plugins than expected, but continuing..."
    fi
    
    print_success "Installation validated"
}

# Show completion message
show_completion() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                     🎉 SETUP COMPLETE! 🎉                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    print_info "Your tmux setup is ready with:"
    echo "  • Catppuccin Mocha theme"
    echo "  • Alt key tap as prefix (via Karabiner)"
    echo "  • Fuzzy session/window finders"
    echo "  • Auto-save/restore sessions"
    echo "  • Enhanced copy/paste"
    echo "  • System monitoring in status bar"
    echo ""
    print_info "Quick start:"
    echo "  • tmux attach -t main    # Attach to startup session"
    echo "  • Alt+tap f             # Fuzzy window finder"
    echo "  • Alt+tap Ctrl+f        # Fuzzy session finder"
    echo "  • Alt+tap ?             # Show all key bindings"
    echo ""
    print_warning "Don't forget to enable Karabiner rule for Alt key tap!"
}

# Main execution
main() {
    print_header
    
    check_dependencies
    check_location
    stow_dotfiles
    install_tpm
    install_fzf
    
    sleep 1  # Brief pause for TPM to be ready
    
    install_plugins
    create_startup_session
    validate_installation
    
    show_completion
}

# Run with error handling
if ! main "$@"; then
    print_error "Setup failed. Check the errors above."
    exit 1
fi 