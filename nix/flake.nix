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
          XDG_DATA_HOME = "${homeDirectory}/.local/share";
          XDG_CACHE_HOME = "${homeDirectory}/.cache";
          XDG_STATE_HOME = "${homeDirectory}/.local/state";
          ZDOTDIR = "$XDG_CONFIG_HOME/zsh";
          CLAUDE_CONFIG_DIR = "${homeDirectory}/.config/claude-code";
        };
      };

      # === PROGRAMS ===
      
      programs.zsh.enable = true;
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # === ACTIVATION SCRIPTS ===
      
      system.activationScripts.applications.text = ''
        # Link yazi plugins in dotfiles directory
        mkdir -p ${homeDirectory}/dotfiles/yazi/plugins
        ln -sf ${pkgs.yaziPlugins.chmod} ${homeDirectory}/dotfiles/yazi/plugins/chmod.yazi 2>/dev/null || true
        ln -sf ${pkgs.yaziPlugins.toggle-pane} ${homeDirectory}/dotfiles/yazi/plugins/toggle-pane.yazi 2>/dev/null || true
      '';

      # rbw declarative config: pinentry + lock_timeout. `config set` is a
      # read-modify-write that only touches the given key, so each line is safe
      # to re-run every rebuild and won't clobber other settings (email,
      # base_url, etc.) that `rbw login` wrote.  Runs as the user (activation is
      # root); `|| true` keeps a hiccup from failing the whole activation.
      #
      # Why absolute /nix/store paths: rbw-agent inherits launchd's PATH (not the
      # user login PATH), so a bare name like "pinentry-rbw-touchid" is fragile.
      #
      # Why lock_timeout=1: pair with the rbw() shell wrapper in zsh/.zshrc —
      # together they relock the agent the moment a secret-fetching command
      # returns, so the master keys don't sit decrypted in agent memory between
      # explicit fetches.
      system.activationScripts.postActivation.text = ''
        sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
          ${pkgs.rbw}/bin/rbw config set pinentry \
          ${packages.pinentry-rbw-touchid}/bin/pinentry-rbw-touchid || true
        sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
          ${pkgs.rbw}/bin/rbw config set lock_timeout 1 || true
      '';

      # === PACKAGE MANAGEMENT ===

      homebrew = {
        enable = true;
        brews = packages.homebrewBrews;
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
