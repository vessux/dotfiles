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

    # bb client wiring (see the bb block further down, and BB.md in the homelab
    # repo). bbVersion must match bb_server_version in roles/bb_server there:
    # server and host daemons speak a versioned protocol, and a mismatch is
    # terminal — the server rejects every daemon session and this machine just
    # stops appearing. bb advertises that an auto-updating daemon repairs this
    # itself; it does not (see the agent block below), so this pin is the only
    # thing keeping the two in step. `just bb-update` in the homelab repo moves
    # bb_server_version and prints a reminder to bump this.
    bbVersion = "0.42.0";
    bbServerUrl = "https://devbox.taile06170.ts.net";
    # The npm bb-app package, NOT the copy inside /Applications/bb.app — that
    # one's better-sqlite3 is built against Electron's ABI (NODE_MODULE_VERSION
    # 145 vs node 24's 137) and aborts on startup under plain node.
    bbClientPrefix = "${homeDirectory}/.local/share/bb-headless";
    # Per-server machine data dir, holding this machine's enrolment secret
    # (auth.json). Named after the server so a second bb never shares it.
    bbMachineDataDir = "${homeDirectory}/.bb-machines/devbox.taile06170.ts.net";

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

      # Nix garbage collection. The usual `nix.gc` options can't be used here:
      # nix.enable = false hands the daemon to Determinate Nix, which ships no
      # GC scheduler, and nix-darwin gates the whole `nix` module behind that
      # flag. launchd.daemons is a separate module, so it works regardless;
      # running as root lets it prune the root-owned system profile's old
      # generations too (a user-run GC only touches per-user profiles).
      # --delete-older-than prunes generations past the cutoff, then collects
      # the store paths they were pinning. Current generation is always kept.
      launchd.daemons.nix-gc = {
        command = "/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 90d";
        serviceConfig = {
          StartCalendarInterval = [ { Weekday = 0; Hour = 3; Minute = 15; } ];
          StandardOutPath = "/var/log/nix-gc.log";
          StandardErrorPath = "/var/log/nix-gc.log";
        };
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
          PI_CODING_AGENT_DIR = "${homeDirectory}/.config/pi/agent";
          PI_CODING_AGENT_SESSION_DIR = "${homeDirectory}/.local/share/pi/sessions";
          PI_SKIP_VERSION_CHECK = "1";
        };
      };

      # bb: this Mac is a THIN CLIENT plus an execution machine. The
      # authoritative bb server runs headless on devbox and is reached over the
      # tailnet (`tailscale serve` in front of its loopback 38886) — see BB.md in
      # the homelab repo. Neither piece below is a dotfile: both live under
      # ~/Library, which Stow (target ~/.config) cannot manage, which is why
      # this belongs in nix-darwin rather than the stowed tree.
      #
      # This agent is a standalone host daemon, and it is NOT optional: in remote
      # mode the desktop app spawns no daemon of its own (it starts one only when
      # its stored server target is "builtin"), so without this you cannot run
      # threads on your own laptop at all.
      #
      # CLAUDE_CONFIG_DIR is set explicitly rather than inherited:
      # environment.variables above reaches shells via /etc/zshenv but NOT
      # launchd, so `launchctl getenv CLAUDE_CONFIG_DIR` is empty and a daemon
      # started at boot would fall back to ~/.claude and report "not logged in".
      # BB_CLAUDE_CODE_EXECUTABLE bypasses the umbel shim, which otherwise kills
      # provider calls with `bundle 'clerk-discovery' not found`.
      #
      # Mirrors roles/bb_server in the homelab repo — keep bbVersion and the two
      # provider variables in step with bb_server_version there.
      launchd.user.agents.bb-host-daemon = {
        serviceConfig = {
          ProgramArguments = [
            "${homeDirectory}/.local/share/mise/shims/node"
            "${bbClientPrefix}/node_modules/bb-app/dist/bb-app.js"
            "host-daemon"
            "--server-url" bbServerUrl
            "--host-daemon-port" "38890"
            # No --auto-update. It is not merely redundant against bbVersion
            # above, it is broken here in two independent, silent ways:
            #   * the daemon installs the new build into BB_APP_NPM_PREFIX
            #     below, but ProgramArguments execs bbClientPrefix — launchd
            #     never runs the updated tree, and KeepAlive restores the old
            #     one on the next restart;
            #   * the install shells out to mise's npm wrapper, which ends with
            #     `mise reshim`. launchd's PATH has no /opt/homebrew/bin, so
            #     that exits 127 AFTER npm unpacked the tree correctly; npm
            #     inherits 127 and bb discards an update that had succeeded.
            # Adding /opt/homebrew/bin to EnvironmentVariables would fix only
            # the second, and would be dead config once the flag is gone.
            # A stale pin is loud (server rejects the session outright); a
            # self-update racing the pin was not. See BB.md in the homelab repo.
          ];
          EnvironmentVariables = {
            BB_DATA_DIR = bbMachineDataDir;
            BB_APP_NPM_PREFIX = "${bbMachineDataDir}/npm";
            CLAUDE_CONFIG_DIR = "${homeDirectory}/.config/claude-code";
            BB_CLAUDE_CODE_EXECUTABLE = "${homeDirectory}/.local/bin/claude";
          };
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${bbMachineDataDir}/launchd.out.log";
          StandardErrorPath = "${bbMachineDataDir}/launchd.err.log";
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

        # gh-stack (stacked PRs) wiring. gh finds extensions ONLY by scanning
        # $XDG_DATA_HOME/gh/extensions for gh-<name>/gh-<name> — never PATH — so
        # the nixpkgs binary needs this symlink to be reachable as `gh stack`.
        # nix owns the version: `gh extension upgrade` sees no manifest, reports
        # "already up to date", and leaves the link alone. Keep the pin in sync
        # with devbox_gh_stack_version in the homelab repo's roles/devbox.
        #
        # Run as the user so the tree isn't root-owned (activation is root) —
        # otherwise later `gh extension` commands fail on permissions. HOME is
        # enough: XDG_DATA_HOME isn't exported here, but gh falls back to the
        # same $HOME/.local/share default.
        sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
          mkdir -p ${homeDirectory}/.local/share/gh/extensions/gh-stack || true
        sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
          ln -sf ${pkgs.gh-stack}/bin/gh-stack \
          ${homeDirectory}/.local/share/gh/extensions/gh-stack/gh-stack || true

        # bb client: the npm bb-app package provides the headless host daemon
        # the launchd agent above runs. Check-then-act on the installed version
        # so a rebuild reinstalls only on a version bump, rather than reaching
        # out to the npm registry on every activation.
        sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
          mkdir -p ${bbClientPrefix} || true
        if [ "$(${homeDirectory}/.local/share/mise/shims/node -p \
              "require('${bbClientPrefix}/node_modules/bb-app/package.json').version" \
              2>/dev/null)" != "${bbVersion}" ]; then
          sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
            ${homeDirectory}/.local/share/mise/shims/npm install \
            --prefix ${bbClientPrefix} bb-app@${bbVersion} \
            --no-audit --no-fund || true
        fi

        # Seed the desktop app's server target so a fresh machine comes up
        # pointing at devbox instead of silently starting its own local server.
        # Written ONLY when absent: the app rewrites this file itself when you
        # pick Window > Server, and clobbering it on every rebuild would revert
        # that choice behind your back.
        sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
          mkdir -p "${homeDirectory}/Library/Application Support/bb" || true
        if [ ! -e "${homeDirectory}/Library/Application Support/bb/server-target.json" ]; then
          sudo -u ${username} /usr/bin/env HOME=${homeDirectory} \
            install -m 644 ${pkgs.writeText "bb-server-target.json" (builtins.toJSON {
              connectServer = null;
              customServerUrl = bbServerUrl;
              target = "custom";
            })} \
            "${homeDirectory}/Library/Application Support/bb/server-target.json" || true
        fi
      '';

      # === PACKAGE MANAGEMENT ===

      homebrew = {
        enable = true;
        brews = packages.homebrewBrews;
        casks = packages.homebrewCasks;
        # masApps disabled: MDM enrollment is broken on this Mac and mas
        # activation fails/hangs because of it. See packages.nix
        # macAppStoreApps for the app list to restore once MDM is fixed.
        masApps = { };
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
