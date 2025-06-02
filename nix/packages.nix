{ nixpkgs, ... }:

{
  # System packages organized by category
  systemPackages = with nixpkgs.legacyPackages.aarch64-darwin; [
    # Development tools
    awscli
    bat
    fd
    fzf
    neovim
    nodejs
    stow
    vim

    # System utilities
    lazydocker
    lazygit
    openfortivpn
    tmux
    unixtools.watch
    watch
    yazi
  ];

  # Homebrew applications organized by category
  homebrewCasks = [
    # Browsers
    "firefox"
    "google-chrome"

    # Development
    "cursor"
    "ghostty"
    "jetbrains-toolbox"
    "lens"
    "orbstack"
    "postman"
    "sublime-text"
    "visual-studio-code"
    "warp"

    # Productivity
    "raycast"
    "shortcat"
    "slack"
    "xmind"

    # Media & Entertainment
    "calibre"
    "discord"
    "epic-games"
    "kodi"
    "steam"
    "vlc"

    # Utilities
    "cheatsheet"
    "datovka"
    "keka"
    "kekaexternalhelper"
    "keycastr"
    "linearmouse"
    "mouseless"
    "nitroshare"
    "ollama"
    "qbittorrent"
    "sync"
  ];

  macAppStoreApps = {
    "Apple developer" = 640199958;
    "Bitwarden" = 1352778147;
    "Trello" = 1278508951;
    "Xcode" = 497799835;
  };
} 