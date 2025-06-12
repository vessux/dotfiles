# Dotfiles

Personal configuration files and setup scripts for my development environment.

## Prerequisites

- macOS (tested on macOS Sonoma 14.0+)
- Git
- Terminal access

## Installation

### 1. Install Nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone this repository

```bash
git clone git@github.com:vessux/dotfiles.git ~/dotfiles
```

### 3. Apply Nix configuration

```bash
sudo nix run nix-darwin -- switch --flake ~/dotfiles/nix
```

### 4. Symlink dotfiles using Stow

```bash
cd ~/dotfiles
stow .
```

## Tmux Setup

Tmux requires a few extra steps for full plugin and shell integration:

### 🚀 One-Click Setup (Recommended)

```bash
cd ~/dotfiles/tmux
./install.sh
```
This will:
- Install TPM (Tmux Plugin Manager)
- Install all plugins
- Create a starter session
- Validate everything

## What's Included

### 🛠️ Development Tools
- **Neovim** - Text editor configuration
- **Tmux** - Terminal multiplexer with custom theme and plugins
- **Git** - Version control configuration and global gitignore
- **Starship** - Cross-platform shell prompt with custom styling
- **Atuin** - Shell history sync and search
- **Bat** - Enhanced cat with syntax highlighting and themes
- **Yazi** - Terminal file manager with plugins and catppuccin theme
- **Zsh** - Shell configuration with custom setup

### 🎨 Terminal & UI
- **Ghostty** - Terminal emulator configuration
- **Karabiner Elements** - Keyboard customization for macOS
- **LinearMouse** - Mouse acceleration and scrolling customization

### 📊 System Utilities
- **Lazygit** - Terminal-based Git interface
- **Lazydocker** - Terminal-based Docker interface
- **qBittorrent** - BitTorrent client configuration
- **Raycast** - Spotlight replacement
- **IdeaVimRC** - Vim configuration for JetBrains IDEs

### 🏗️ System Management
- **Nix Darwin** - Declarative macOS system configuration
  - Package management (Nix packages + Homebrew casks)
  - System defaults and preferences
  - Symbolic hotkey configurations
  - Font installation (JetBrains Mono Nerd Font, Hack Nerd Font)
  - macOS security settings (Touch ID for sudo)

### 📁 Configuration Structure

All configurations are symlinked to `~/.config/` via Stow:

```
~/.config/
├── atuin/          # Shell history configuration
├── bat/            # Syntax highlighter configuration  
├── ghostty/        # Terminal emulator configuration
├── git/            # Git configuration and global gitignore
├── karabiner/      # Keyboard customization
├── lazydocker/     # Docker TUI configuration
├── lazygit/        # Git TUI configuration
├── linearmouse/    # Mouse configuration
├── qBittorrent/    # BitTorrent client configuration
├── starship/       # Shell prompt configuration
├── tmux/           # Terminal multiplexer configuration
├── yazi/           # File manager configuration
├── zsh/            # Shell configuration
└── ideavimrc/      # Vim configuration for IDEs
```

## Customization

Feel free to fork this repository and customize the configurations to suit your needs. The Nix configuration allows for declarative system management, making it easy to reproduce the setup on new machines.

## License

This project is open source and available under the [MIT License](LICENSE).