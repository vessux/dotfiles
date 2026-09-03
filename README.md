# Dotfiles

Personal configuration files and setup scripts for my development environment.

## Prerequisites

- macOS (tested on macOS Sonoma 14.0+)
- Git
- Terminal access

## Installation

### 1. Install Nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone this repository

```bash
git clone git@github.com:vessux/dotfiles.git ~/dotfiles
```

### 3. Apply Nix configuration

```bash
sudo nix run nix-darwin -- switch --flake ~/dotfiles/nix
```

### 4. Symlink dotfiles using Stow

```bash
cd ~/dotfiles
stow .
```

## Tmux Setup

Tmux requires a few extra steps for full plugin and shell integration:

### 🚀 One-Click Setup (Recommended)

```bash
cd ~/dotfiles/tmux
./install.sh
```
This will:
- Install TPM (Tmux Plugin Manager)
- Install all plugins
- Create a starter session
- Validate everything

## Umbel Setup

[Umbel](https://www.npmjs.com/package/@vessux/umbel) composes Claude Code
sessions from named bundles of skills, hooks, and MCP servers. The bundle
config (`~/.config/umbel/`) is stowed from this repo; the binary and PATH
shim are set up once per machine:

```bash
npm i -g @vessux/umbel   # the `umbel` binary
umbel shim install       # writes ~/.local/share/umbel/bin/claude
```

The PATH entry for the shim is already wired in `zsh/.zshrc`, so plain
`claude` resolves through Umbel and picks up a project's bundle.

Bundles live in `~/.config/umbel/bundles/*.md`. Some declare external binary
prerequisites (e.g. `plannotator`, `tuidriver`) — each bundle's `.md`
documents its own install step.

## BB Setup

This Mac is a **thin client plus an execution machine**. The authoritative bb
server runs headless on devbox and is reached over the tailnet; see `BB.md` in
the homelab repo for the full topology and recovery steps.

Nothing here is stowed. Both Mac-side pieces live under `~/Library`, which Stow
(target `~/.config`) cannot manage, so they are declared in `nix/flake.nix`
instead:

- `launchd.user.agents.bb-host-daemon` — a standalone host daemon. Not optional:
  in remote mode the desktop app spawns no daemon of its own (it starts one only
  when its stored server target is `builtin`), so without it you cannot run
  threads on this Mac at all.
- A `postActivation` step that installs the pinned `bb-app` npm package and
  seeds `Library/Application Support/bb/server-target.json`. The seed is written
  only when absent — the app rewrites that file whenever you use
  **Window > Server**, and clobbering it every rebuild would revert your choice.

Two environment variables in the agent are load-bearing, both learned the hard
way:

- `CLAUDE_CONFIG_DIR` is set **explicitly**, not inherited. `environment.variables`
  reaches shells via `/etc/zshenv` but not launchd, so `launchctl getenv
  CLAUDE_CONFIG_DIR` is empty and a daemon started at boot would fall back to
  `~/.claude` and report "not logged in".
- `BB_CLAUDE_CODE_EXECUTABLE` points at the real binary so provider calls bypass
  the Umbel shim, which otherwise fails with `bundle 'clerk-discovery' not found`
  and surfaces only as a thread that never starts.

Keep `bbVersion` in `nix/flake.nix` in step with `bb_server_version` in the
homelab repo's `roles/bb_server`: server and host daemons speak a versioned
protocol, and on a mismatch the daemon re-downloads the server's build on every
connect.

The devbox side — server, unit, tailnet publication — is Ansible's job, not
this repo's. There is deliberately no stowed `bb/` package and no systemd
drop-in here any more.

## Pi Setup

[Pi](https://pi.dev/) is installed as the Homebrew formula
`pi-coding-agent`, which provides the `pi` CLI. This mirrors the Claude Code
setup policy: Homebrew owns fast-moving coding-agent CLIs, while dotfiles own
shell/config glue.

Global Pi config is redirected with `PI_CODING_AGENT_DIR` to
`~/.config/pi/agent`, so Stow can manage it alongside the rest of this repo.
Pi sessions are kept out of the stowed config tree with
`PI_CODING_AGENT_SESSION_DIR=~/.local/share/pi/sessions` (set as an absolute
path by Nix because Pi settings support absolute/relative paths and `~`, but
not `$XDG_DATA_HOME` interpolation). `PI_SKIP_VERSION_CHECK=1` keeps version
prompting aligned with that policy: Homebrew/Brew Bundle owns upgrades, not
Pi's startup check.

Tracked Pi config lives under `pi/agent/`. The whitelist in `.gitignore`
tracks `settings.json`, future config files such as `keybindings.json`, system
prompt files, plus the user-authored `skills/`, `prompts/`, `themes/`, and
opt-in extension directories. Each tracked extension directory should include
its own `.gitignore` to re-include source/lockfiles and ignore installed or
generated local artifacts such as `node_modules/`. The regenerable model
catalog `pi/agent/models.json` stays ignored; refresh it with
`bin/pi-sync-nvidia-models`. Runtime state such as `auth.json`, `trust.json`,
`npm/`, `git/`, logs, temp files, extension dependencies, and ad-hoc installed
extensions stays ignored by default.

Directory-style extensions under `pi/agent/extensions/<name>/index.ts` are
auto-discovered by Pi after Stow links them into `~/.config/pi/agent/extensions/`.

After applying the Nix Darwin config, run Pi from a project directory:

```bash
pi
```

### Gondolin

Gondolin runs Pi's built-in tools and `!` commands inside a local Linux
micro-VM while keeping Pi auth/config on the host. The extension source is
tracked at `pi/agent/extensions/gondolin` and stowed to
`~/.config/pi/agent/extensions/gondolin`. The Nix Darwin config installs the
required QEMU runtime through Homebrew; Node >= 23.6.0 is provided by mise and
by Homebrew's Pi dependency.

Install the extension dependencies after Stow has linked the dotfiles:

```bash
pi_agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.config/pi/agent}"
cd "$pi_agent_dir/extensions/gondolin"
npm ci --ignore-scripts
```

Run Pi with Gondolin from the project you want mounted into the VM:

```bash
pi
```

## What's Included

### 🛠️ Development Tools
- **Neovim** - Text editor configuration
- **Tmux** - Terminal multiplexer with custom theme and plugins
- **Git** - Version control configuration and global gitignore
- **Starship** - Cross-platform shell prompt with custom styling
- **Atuin** - Shell history sync and search
- **Bat** - Enhanced cat with syntax highlighting and themes
- **Yazi** - Terminal file manager with plugins and catppuccin theme
- **Zsh** - Shell configuration with custom setup
- **Umbel** - Claude Code bundle config: skills, hooks, and MCP servers (see [Umbel Setup](#umbel-setup))
- **Pi** - Minimal terminal coding agent installed through Homebrew

### 🎨 Terminal & UI
- **Ghostty** - Terminal emulator configuration
- **Karabiner Elements** - Keyboard customization for macOS
- **LinearMouse** - Mouse acceleration and scrolling customization

### 📊 System Utilities
- **Lazygit** - Terminal-based Git interface
- **Lazydocker** - Terminal-based Docker interface
- **Raycast** - Spotlight replacement
- **IdeaVimRC** - Vim configuration for JetBrains IDEs

### 🏗️ System Management
- **Nix Darwin** - Declarative macOS system configuration
  - Package management (Nix packages + Homebrew casks)
  - System defaults and preferences
  - Symbolic hotkey configurations
  - Font installation (JetBrains Mono Nerd Font, Hack Nerd Font)
  - macOS security settings (Touch ID for sudo)

### 📁 Configuration Structure

All configurations are symlinked to `~/.config/` via Stow:

```
~/.config/
├── atuin/          # Shell history configuration
├── bat/            # Syntax highlighter configuration
├── bb/             # BB config plus ignored local runtime state (BB_DATA_DIR)
├── bin/            # Reusable repo scripts on PATH (see ADR 0001)
├── ccstatusline/   # Claude Code status line configuration
├── claude-code/    # Claude Code app configuration
├── ghostty/        # Terminal emulator configuration
├── git/            # Git configuration and global gitignore
├── ideavimrc/      # Vim configuration for IDEs
├── karabiner/      # Keyboard customization
├── launchd/        # macOS launch agents
├── lazydocker/     # Docker TUI configuration
├── lazygit/        # Git TUI configuration
├── linearmouse/    # Mouse configuration
├── mise/           # Dev-tool version manager configuration
├── nix/            # Nix Darwin system configuration
├── npm/            # npm configuration
├── nvim/           # Neovim configuration
├── pi/             # Pi coding agent config (PI_CODING_AGENT_DIR)
├── starship/       # Shell prompt configuration
├── systemd/        # Linux user-service drop-ins
├── tmux/           # Terminal multiplexer configuration
├── umbel/          # Claude Code bundles (skills, hooks, MCP servers)
├── yazi/           # File manager configuration
└── zsh/            # Shell configuration
```

## Customization

Feel free to fork this repository and customize the configurations to suit your needs. The Nix configuration allows for declarative system management, making it easy to reproduce the setup on new machines.

## License

This project is open source and available under the [MIT License](LICENSE).
