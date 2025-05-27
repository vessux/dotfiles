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

## What's Included

- `.config/` - Configuration files for various tools
  - Neovim, yazi, lazygit, lazydocker, and more
- Nix configurations
- Git configurations
- Shell configurations (zsh)

## Customization

Feel free to fork this repository and customize the configurations to suit your needs.

## License

This project is open source and available under the [MIT License](LICENSE).