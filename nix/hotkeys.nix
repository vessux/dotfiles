{ ... }:

let
  # Helper function to create symbolic hotkey entries
  mkHotkey = enabled: parameters: {
    inherit enabled;
    value = {
      inherit parameters;
      type = "standard";
    };
  };
in
{
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
} 