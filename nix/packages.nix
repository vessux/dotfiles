{ nixpkgs, ... }:

let
  # Import nixpkgs for the current system with unfree packages enabled
  pkgs = import nixpkgs {
    system = "aarch64-darwin";
    config = {
      allowUnfree = true;
    };
  };

  # Touch-ID-gated pinentry for rbw. Source lives in ./pkgs; the derivation
  # builds via the host's swiftc + Xcode SDK (see that dir's default.nix).
  pinentry-rbw-touchid = pkgs.callPackage ./pkgs/pinentry-rbw-touchid {};
in
{
  # Re-export so flake.nix can reference the same store path in activation
  # scripts (we set rbw's pinentry to its absolute /nix/store/.../bin/... path).
  inherit pinentry-rbw-touchid;

  # System packages organized by category
  systemPackages = with pkgs; [
    # Development tools
    ast-grep
    atuin
    awscli
    bat
    bun
    cmake
    dotnet-sdk
    eza
    fd
    fzf
    ghostscript
    go
    imagemagick
    jq
    just
    lazysql
    lua5_1
    luarocks
    mermaid-cli
    neovim
    nodejs
    php
    poetry
    ripgrep
    rustup
    stow
    tectonic
    tree-sitter
    uv
    vim
    yq
    zig
    zoxide

    # System utilities
    dust
    lazydocker
    lazygit
    librsvg
    openfortivpn
    pinentry_mac        # GUI pinentry fallback used by pinentry-rbw-touchid
    pinentry-rbw-touchid # Touch-ID-gated pinentry that backs rbw (./pkgs)
    rbw
    starship
    terminal-notifier
    tmux
    unixtools.watch
    watch
    zellij

    # yazi
    yazi
    yaziPlugins.chmod
    yaziPlugins.toggle-pane
    ueberzugpp
  ];

  # Homebrew applications organized by category
  homebrewCasks = [
    # Browsers
    "firefox"
    "google-chrome"
    "zen"

    # Development
    "claude"
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
    "yacreader"

    # Utilities
    "cheatsheet"
    "datovka"
    "karabiner-elements"
    "keka"
    "kekaexternalhelper"
    "keycastr"
    "linearmouse"
    "mouseless"
    "nitroshare"
    "ollama-app"
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
