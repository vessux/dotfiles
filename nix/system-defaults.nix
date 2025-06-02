{ ... }:

{
  systemDefaults = {
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

      # Custom keyboard layout
      "com.apple.HIToolbox" = {
        AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.Czech";
        AppleDictationAutoEnable = 1;
        AppleEnabledInputSources = [
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
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = "-14193";
            "KeyboardLayout Name" = "Czech";
          }
        ];
        AppleFnUsageType = 1;
        AppleInputSourceHistory = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = "-14193";
            "KeyboardLayout Name" = "Czech";
          }
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = "-1";
            "KeyboardLayout Name" = "Unicode Hex Input";
          }
        ];
        AppleSelectedInputSources = [
          {
            "Bundle ID" = "com.apple.PressAndHold";
            InputSourceKind = "Non Keyboard Input Method";
          }
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = "-14193";
            "KeyboardLayout Name" = "Czech";
          }
        ];
      };
    };
  };
} 