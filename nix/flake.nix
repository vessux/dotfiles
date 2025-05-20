{
  description = "System configuration with Nix flakes, Homebrew, and Stow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      # due to using determinate distro
      nix.enable = false;

      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = with pkgs; [
        vim
	      stow
	      awscli
	      lazygit
	      neovim
	      openfortivpn
	      tmux
	      watch
	      unixtools.watch
        yazi
        lazydocker
      ];

      # Manage Homebrew for casks
      homebrew = {
        enable = true;
      casks = [
        # general apps
        "google-chrome"
        "keka"
        "kekaexternalhelper"
        "kodi"
        "firefox"
        "calibre"
        "cheatsheet"
        "datovka"
        "discord"
        "epic-games"
        "linearmouse"
        "nitroshare"
        "qbittorrent"
        "steam"
        "keycastr"
        "vlc"
        "slack"
        "raycast"
        "cursor"
        "mouseless"
        "ollama"
        "sync"
        "visual-studio-code"

        # dev apps
        "sublime-text"
        "jetbrains-toolbox"
        "lens"
        "orbstack"
        "postman"
        "warp"
        "ghostty"
        "shortcat"
        "xmind"
      ];
      masApps = {
        "Xcode" = 497799835;
        "Apple developer" = 640199958;
        "Trello" = 1278508951;
        "Bookplayer" = 1138219998;
        "Bitwarden" = 1352778147;
      };
    };

    # Necessary for using flakes on this system.
    nix.settings.experimental-features = "nix-command flakes";

    # Enable alternative shell support in nix-darwin.
    # programs.fish.enable = true;
    programs.zsh.enable = true;

    environment.variables = {
      XDG_CONFIG_HOME = "/Users/kovis/.config";
      ZDOTDIR = "$XDG_CONFIG_HOME/zsh";
    };

    # Set Git commit hash for darwin-version.
    system.configurationRevision = self.rev or self.dirtyRev or null;

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    system.stateVersion = 6;

    # The platform the configuration will be used on.
    nixpkgs.hostPlatform = "aarch64-darwin";

    # Declare the user that will be running `nix-darwin`.
    users.users.kovis = {
        name = "kovis";
        home = "/Users/kovis";
    };

	  #- Previously, some nix-darwin options applied to the user running
    #`darwin-rebuild`. As part of a long‐term migration to make
    #nix-darwin focus on system‐wide activation and support first‐class
    #multi‐user setups, all system activation now runs as `root`, and
    #these options instead apply to the `system.primaryUser` user.
    #
    #You currently have the following primary‐user‐requiring options set:
    #
    #* `homebrew.enable`
    #
    #To continue using these options, set `system.primaryUser` to the name
    #of the user you have been using to run `darwin-rebuild`. In the long
    #run, this setting will be deprecated and removed after all the
    #functionality it is relevant for has been adjusted to allow
    #specifying the relevant user separately, moved under the
    #`users.users.*` namespace, or migrated to Home Manager.
    #
    #If you run into any unexpected issues with the migration, please
    #open an issue at <https://github.com/nix-darwin/nix-darwin/issues/new>
    #and include as much information as possible.
	  system.primaryUser = "kovis";

    # Configure fonts
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];

    # touch id for cli sudo
    security.pam.services.sudo_local.touchIdAuth = true;
  };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."BigMac-2024" = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
