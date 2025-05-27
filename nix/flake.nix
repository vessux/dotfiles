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
    
    # Helper function to create symbolic hotkey entries
    mkHotkey = enabled: parameters: {
      inherit enabled;
      value = {
        inherit parameters;
        type = "standard";
      };
    };

    # System packages organized by category
    systemPackages = with nixpkgs.legacyPackages.aarch64-darwin; [
      # Development tools
      awscli
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

    # Symbolic hotkeys configuration  
    symbolicHotkeys = {
      # Disabled system shortcuts for clean custom keyboard layout
      "15" = mkHotkey false []; # Turn zoom on/off - Cmd+Opt+8
      "16" = mkHotkey false []; # Zoom functionality
      "17" = mkHotkey false []; # Zoom in - Cmd+Opt+=
      "18" = mkHotkey false []; # Zoom functionality
      "19" = mkHotkey false []; # Zoom out - Cmd+Opt+-
      "20" = mkHotkey false []; # Zoom functionality
      "21" = mkHotkey false []; # Reverse Black and White - Cmd+Ctrl+Opt+8
      "22" = mkHotkey false []; # Accessibility feature
      "23" = mkHotkey false []; # Turn image smoothing on/off - Cmd+Opt+\
      "24" = mkHotkey false []; # Accessibility feature
      "25" = mkHotkey false []; # Increase Contrast - Cmd+Ctrl+Opt+.
      "26" = mkHotkey false []; # Decrease Contrast - Cmd+Ctrl+Opt+,
      "60" = mkHotkey false []; # Select previous input source - Cmd+Opt+Space
      "61" = mkHotkey false []; # Select next input source - Cmd+Opt+Shift+Space
      "64" = mkHotkey false []; # Show Spotlight search field - Cmd+Shift+Space
      "118" = mkHotkey false []; # Switch to Space 1 - Ctrl+1
      "119" = mkHotkey false []; # Switch to Space 2 - Ctrl+2
      "120" = mkHotkey false []; # Switch to Space 3 - Ctrl+3
      "164" = mkHotkey false []; # Accessibility Options
      
      # Enabled custom shortcuts for Kanata integration
      "27" = mkHotkey true [ 99 8 917504 ]; # Window cycling (remapped to 'c' key)
      "79" = mkHotkey true [ 65535 123 10747904 ]; # Spaces Left (custom modifiers)
      "80" = mkHotkey true [ 65535 123 10878976 ]; # Spaces Left (variant)
      "81" = mkHotkey true [ 65535 124 8650752 ]; # Spaces Right (custom modifiers)
      "82" = mkHotkey true [ 65535 124 8781824 ]; # Spaces Right (variant)
    };

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

      # === USER MANAGEMENT ===
      
      users.users.${username} = {
        name = username;
        home = homeDirectory;
      };

      # === ENVIRONMENT ===
      
      environment = {
        systemPackages = systemPackages;
        systemPath = [ "/opt/homebrew/bin" ];
        variables = {
          XDG_CONFIG_HOME = "${homeDirectory}/.config";
          ZDOTDIR = "$XDG_CONFIG_HOME/zsh";
        };
      };

      # === PROGRAMS ===
      
      programs.zsh.enable = true;

      # === PACKAGE MANAGEMENT ===
      
      homebrew = {
        enable = true;
        casks = homebrewCasks;
        masApps = macAppStoreApps;
      };

      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
      ];

      # === SECURITY ===
      
      security.pam.services.sudo_local.touchIdAuth = true;

      # === SYSTEM DEFAULTS ===
      
      system.defaults = {
        # Dock configuration
        dock = {
          autohide = false;
          orientation = "right";
          show-recents = false;
        };

        # Keyboard configuration
        hitoolbox = {
          AppleFnUsageType = "Change Input Source";
        };

        # Finder configuration
        finder = {
          AppleShowAllExtensions = true;
          AppleShowAllFiles = true;
          FXDefaultSearchScope = "SCcf"; # Search current folder by default
          FXEnableExtensionChangeWarning = false;
          FXPreferredViewStyle = "clmv"; # Column view
          ShowPathbar = true;
          ShowStatusBar = true;
        };

        # Trackpad configuration
        trackpad = {
          ActuationStrength = 0; # Silent clicking
          Clicking = true; # Tap to click
          TrackpadRightClick = true;
          TrackpadThreeFingerDrag = false; # Disable three finger drag
          TrackpadThreeFingerTapGesture = 0; # Disable Look up & data detectors
          FirstClickThreshold = 1; # Light click pressure
          SecondClickThreshold = 1; # Light force touch pressure
        };

        # Global domain settings
        NSGlobalDomain = {
          # Interface & Appearance
          AppleInterfaceStyle = "Dark"; # Dark mode
          AppleScrollerPagingBehavior = true; # Jump to spot clicked on scroll bar
          
          # File handling
          AppleShowAllExtensions = true;
          AppleShowAllFiles = true;
          
          # Disable auto-correction features
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticDashSubstitutionEnabled = false;
          NSAutomaticPeriodSubstitutionEnabled = false; # Disable double-space period
          NSAutomaticQuoteSubstitutionEnabled = false;
          NSAutomaticSpellingCorrectionEnabled = false;
        };

        # Login window
        loginwindow.GuestEnabled = false;

        # Control Center
        controlcenter = {
          BatteryShowPercentage = true;
          Display = false; # Hide display controls in menu bar
          FocusModes = false; # Hide focus modes in menu bar
        };

        # Custom application preferences
        CustomUserPreferences = {
          # Prevent .DS_Store files on network/USB volumes
          "com.apple.desktopservices" = {
            DSDontWriteNetworkStores = true;
            DSDontWriteUSBStores = true;
          };
          
          # Screen saver security
          "com.apple.screensaver" = {
            askForPassword = 1;
            askForPasswordDelay = 0;
          };
          
          # System services
          "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
          "com.apple.ImageCapture".disableHotPlug = true;
          "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
          
          # Software updates
          "com.apple.SoftwareUpdate" = {
            AutomaticCheckEnabled = true;
            AutomaticDownload = 1;
            CriticalUpdateInstall = 1;
            ScheduleFrequency = 1; # Daily
          };

          # Symbolic hotkeys for Kanata keyboard layout integration
          "com.apple.symbolichotkeys".AppleSymbolicHotKeys = symbolicHotkeys;

          # Custom keyboard layout
          "com.apple.HIToolbox" = {
            AppleDictationAutoEnable = 1;
            AppleEnabledInputSources = [
              {
                InputSourceKind = "Keyboard Layout";
                "KeyboardLayout ID" = "-14193";
                "KeyboardLayout Name" = "Czech";
              }
              {
                "Bundle ID" = "com.apple.CharacterPaletteIM";
                InputSourceKind = "Non Keyboard Input Method";
              }
              {
                "Bundle ID" = "com.apple.PressAndHold";
                InputSourceKind = "Non Keyboard Input Method";
              }
              {
                "Bundle ID" = "com.apple.inputmethod.ironwood";
                InputSourceKind = "Non Keyboard Input Method";
              }
              {
                InputSourceKind = "Keyboard Layout";
                "KeyboardLayout ID" = "-1";
                "KeyboardLayout Name" = "Unicode Hex Input";
              }
            ];
            AppleFnUsageType = 1;
          };
        };
      };
    };
  in
  {
    # Darwin configuration
    darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
