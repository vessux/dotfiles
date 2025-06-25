{
  description = "Personal macOS system configuration with Nix Darwin, Homebrew, and custom dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    # System configuration
    hostname = "BigMac-2024";
    username = "kovis";
    homeDirectory = "/Users/${username}";
    
    # Import module configurations
    packages = import ./packages.nix { inherit nixpkgs; };
    hotkeys = import ./hotkeys.nix { };
    systemDefaults = import ./system-defaults.nix { };

    configuration = { pkgs, ... }: {
      # === SYSTEM CORE ===
      
      # Nix configuration
      nix = {
        enable = false; # Using Determinate Systems Nix
        settings.experimental-features = "nix-command flakes";
      };

      # System metadata
      system = {
        configurationRevision = self.rev or self.dirtyRev or null;
        stateVersion = 6;
        primaryUser = username;
      };

      # Platform
      nixpkgs.hostPlatform = "aarch64-darwin";

      # Allow unfree packages system-wide (e.g., claude-code)
      nixpkgs.config.allowUnfree = true;

      # === USER MANAGEMENT ===
      
      users.users.${username} = {
        name = username;
        home = homeDirectory;
      };

      # === ENVIRONMENT ===
      
      environment = {
        systemPackages = packages.systemPackages;
        systemPath = [ "/opt/homebrew/bin" ];
        variables = {
          XDG_CONFIG_HOME = "${homeDirectory}/.config";
          ZDOTDIR = "$XDG_CONFIG_HOME/zsh";
        };
      };

      # === PROGRAMS ===
      
      programs.zsh.enable = true;

      # === ACTIVATION SCRIPTS ===
      
      system.activationScripts.applications.text = ''
        # Link yazi plugins in dotfiles directory
        mkdir -p ${homeDirectory}/dotfiles/yazi/plugins
        ln -sf ${pkgs.yaziPlugins.chmod} ${homeDirectory}/dotfiles/yazi/plugins/chmod.yazi 2>/dev/null || true
        ln -sf ${pkgs.yaziPlugins.toggle-pane} ${homeDirectory}/dotfiles/yazi/plugins/toggle-pane.yazi 2>/dev/null || true
      '';

      # === PACKAGE MANAGEMENT ===
      
      homebrew = {
        enable = true;
        casks = packages.homebrewCasks;
        masApps = packages.macAppStoreApps;
      };

      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.hack
      ];

      # === SECURITY ===
      
      security.pam.services.sudo_local = {
        touchIdAuth = true;
        reattach = true;
      };

      # === SYSTEM DEFAULTS ===
      
      system.defaults = systemDefaults.systemDefaults // {
        # Merge symbolic hotkeys with other custom preferences
        CustomUserPreferences = systemDefaults.systemDefaults.CustomUserPreferences // {
          "com.apple.symbolichotkeys".AppleSymbolicHotKeys = hotkeys.symbolicHotkeys;
        };
      };
    };
  in
  {
    nixpkgsConfig = {
      allowUnfree = true;
    };

    # Darwin configuration
    darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
