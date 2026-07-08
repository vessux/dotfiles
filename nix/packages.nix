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

  # rbw wrapped so EVERY caller — interactive shells, bash scripts, ansible,
  # cron — records the operation before the vault unlocks and re-locks the agent
  # after a secret read. The record is the ~/Library/Caches/rbw-touchid-ctx
  # "sticky note" that pinentry-rbw-touchid reads to label the Touch ID popup
  # ("Unlock rbw vault — rbw get github" instead of a bare "Unlock rbw vault").
  # This supersedes the old zsh rbw() function, which only covered interactive
  # shells — scripts called the bare binary and got the generic popup.
  #
  # symlinkJoin keeps the real rbw-agent (+ man pages / completions) on PATH; the
  # wrapper forwards to ${pkgs.rbw}/bin/rbw by absolute store path, so it never
  # recurses into itself. writeShellScriptBin adds no `set -e`, so the exit code
  # of rbw is captured rather than aborting before the re-lock/cleanup.
  rbw-touchid =
    let
      wrapper = pkgs.writeShellScriptBin "rbw" ''
        ctx="$HOME/Library/Caches/rbw-touchid-ctx"
        printf '%s\n' "$*" > "$ctx" 2>/dev/null
        ${pkgs.rbw}/bin/rbw "$@"; ec=$?
        case "$1" in get|code) ${pkgs.rbw}/bin/rbw lock >/dev/null 2>&1 ;; esac
        rm -f "$ctx" 2>/dev/null
        exit $ec
      '';
    in
    pkgs.symlinkJoin {
      name = "rbw-touchid";
      paths = [ wrapper pkgs.rbw ];
    };
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
    gh
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
    lima
    openfortivpn
    pinentry_mac        # GUI pinentry fallback used by pinentry-rbw-touchid
    pinentry-rbw-touchid # Touch-ID-gated pinentry that backs rbw (./pkgs)
    podman
    rbw-touchid          # rbw client + agent, wrapped to label the unlock popup
    starship
    terminal-notifier
    tmux
    unixtools.watch
    wakeonlan
    watch
    zellij

    # yazi
    yazi
    yaziPlugins.chmod
    yaziPlugins.toggle-pane
    ueberzugpp
  ];

  # Homebrew CLI formulae kept on brew on purpose:
  #   mas   — backs masApps during nix-darwin activation
  #   mise  — fast calver; brew stays fresher than nixpkgs
  #   beads — nixpkgs lags a major (steveyegge/beads); dolt + icu4c@78 ride along
  #   llama.cpp — multiple builds/day; brew runs ~700 builds ahead of nixpkgs,
  #           and freshness matters for model/perf support (replaced ollama)
  #   pi-coding-agent — fast-moving coding-agent CLI; Homebrew packages the
  #           official npm tarball with npm lifecycle scripts disabled
  homebrewBrews = [
    "mas"
    "mise"
    "beads"
    "llama.cpp"
    "pi-coding-agent"
  ];

  # Homebrew applications organized by category
  homebrewCasks = [
    # Browsers
    "firefox"
    "google-chrome"
    "zen"

    # Development
    "claude"
    "ghostty"
    "lens"
    "orbstack"
    "sublime-text"
    "visual-studio-code"

    # Productivity
    "raycast"
    "shortcat"
    "slack"
    "xmind"
    "opensuperwhisper"

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
    "sync"
    "thaw@beta"
  ];

  macAppStoreApps = {
    "Amphetamine" = 937984704;
    "Apple developer" = 640199958;
    "Bitwarden" = 1352778147;
    "Trello" = 1278508951;
    "Xcode" = 497799835;
    "Xnip" = 1221250572;
  };
} 
