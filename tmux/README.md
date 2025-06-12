# Tmux Beginner's Guide

## Installation & Setup

### 🚀 One-Click Setup (Recommended)

```bash
cd ~/dotfiles/tmux
./install.sh
```

**What the script does:**
- ✅ Stows dotfiles automatically
- ✅ Installs TPM (Tmux Plugin Manager)
- ✅ Installs all plugins
- ✅ Creates a "main" startup session
- ✅ Validates everything works
- ✅ Shows you what to do next

### 📋 Manual Setup (Alternative)

**1. Stow the dotfiles (from ~/dotfiles root):**
```bash
cd ~/dotfiles
stow .
```

**2. Install TPM (Tmux Plugin Manager):**
```bash
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
```

**3. Install plugins:**
- Start tmux: `tmux`
- Press `Ctrl-a I` (capital i) to install plugins
- Wait for installation to complete

## Basic Usage

### Starting Tmux
```bash
tmux                    # Start new session
tmux new -s myname      # Start new session with name
tmux attach -t myname   # Attach to named session
tmux ls                 # List sessions
```

### Features

✨ **Catppuccin Mocha Theme**: Beautiful pastel colors with a cozy dark aesthetic  
🎨 **Spunky Visual Design**: Purple active panes, pink/blue status bar highlights  
🖱️ **Mouse Support**: Click to switch panes, drag to resize, scroll naturally  
⌨️ **Vim-like Navigation**: `h/j/k/l` for intuitive pane movement  
🚀 **Which-Key Menu**: Discoverable command palette - never memorize shortcuts again!  

## Key Bindings (Prefix: Ctrl-a)

**Session Management:**
- `Ctrl-a d` - Detach from session
- `Ctrl-a s` - List and switch sessions
- `Ctrl-a Ctrl-f` - Fuzzy find sessions (popup)
- `Ctrl-a f` - Fuzzy find windows (popup)

**Windows (Tabs):**
- `Ctrl-a c` - Create new window
- `Ctrl-a ,` - Rename current window
- `Ctrl-a n` - Next window
- `Ctrl-a p` - Previous window
- `Ctrl-a 0-9` - Switch to window by number

**Panes (Split Screen):**
- `Ctrl-a |` - Split horizontally (side by side)
- `Ctrl-a -` - Split vertically (top/bottom)
- `Ctrl-a h/j/k/l` - Navigate panes (vim-style)
- `Ctrl-a H/J/K/L` - Resize panes
- `Ctrl-a x` - Close current pane
- `Ctrl-a z` - Zoom/unzoom current pane

**Copy Mode:**
- `Ctrl-a [` - Enter copy mode
- `v` - Start selection
- `y` - Copy selection
- `Ctrl-a ]` - Paste

**Which-Key Menu:**
- `Ctrl-a Space` - Show command menu with organized actions
- `Ctrl-Space` - Show command menu from anywhere (no prefix needed)

**Useful:**
- `Ctrl-a r` - Reload config
- `Ctrl-a ?` - Show all key bindings
- `Ctrl-a Ctrl-l` - Clear screen and history

**Plugin Features:**
- `Ctrl-a Ctrl-s` - Save session (resurrect)
- `Ctrl-a Ctrl-r` - Restore session (resurrect)
- `Ctrl-a /` - Search text in panes (copycat)
- `Ctrl-a Ctrl-f` - Search files (copycat)
- `Ctrl-a Ctrl-u` - Search URLs (copycat)
- `Ctrl-a o` - Open highlighted file/URL (open)

## Awesome Plugins Included 🚀

**🔄 Session Management:**
- **resurrect** + **continuum**: Auto-save/restore sessions every 15 minutes
- Your work survives reboots, crashes, and coffee spills

**📋 Enhanced Copy/Paste:**
- **tmux-yank**: Better clipboard integration with system
- **copycat**: Search and highlight text, files, URLs with regex

**📊 Status Bar Info:**
- **CPU usage**: Real-time CPU percentage
- **Battery**: Battery percentage for laptops
- **Prefix highlight**: Visual indicator when prefix key is pressed

**🧭 Navigation:**
- **vim-tmux-navigator**: Seamless switching between vim/nvim and tmux panes
- **tmux-fzf**: Fuzzy finder popups for sessions, windows, panes
- **tmux-open**: Open files/URLs directly from tmux
- **tmux-which-key**: Which-key style command menu - discover actions intuitively

**⚙️ Quality of Life:**
- **tmux-sensible**: Sensible defaults that just work

## Smart Session Management 🧠

### **Auto-Attach Behavior:**

Add this to your `~/.zshrc` to make `tmux` always attach to existing sessions:

```bash
# Source the shell integration
source ~/.config/tmux/shell-integration.sh
```

**What you get:**
- **`tmux`** → Attaches to existing session or creates "main"
- **`tmp`** → Project session (uses current directory name)  
- **`tms`** → Fuzzy session selector (requires fzf)
- **`tmkill`** → Interactive session killer (requires fzf)
- **`tmdev`** → Creates development session with 4 windows

### **Quick Commands:**
```bash
tmux             # Smart attach to any existing session
tmp              # Project session for current directory
tms              # Fuzzy session picker (requires fzf)
tmkill           # Interactive session killer (requires fzf)
tml              # List sessions
tmka             # Kill all sessions
tmnuke           # Nuclear option - kill all sessions and wipe save history
```

## Pro Tips

1. **Smart Session Workflow**: Use `tmp` in each project directory for organized sessions
2. **Auto-Restore**: Sessions automatically restore on tmux start - never lose work again
3. **Fuzzy Everything**: `tms` for session picker, `Ctrl-a f` for windows
4. **Plugin Management**: `Ctrl-a I` to install, `Ctrl-a U` to update plugins
5. **Development Setup**: `tmdev` creates perfect coding environment
6. **Session Persistence**: With continuum plugin, sessions survive reboots

## Common Workflows

### Development Setup
```bash
tmp               # Create/attach to project session (uses directory name)
Ctrl-a c          # New window for editor
Ctrl-a -          # Split for terminal
Ctrl-a h          # Switch back to editor pane
```

### Monitoring Setup
```bash
tmux new -s monitoring
Ctrl-a |          # Split horizontally
# Left: htop, Right: tail -f logs
```

## Plugin Management

**Install new plugins:**
1. Add plugin line to config: `set -g @plugin 'author/plugin-name'`
2. Reload tmux: `Ctrl-a r`
3. Install: `Ctrl-a I`

**Update plugins:** `Ctrl-a U`
**Remove plugins:** `Ctrl-a alt-u` (after removing from config)

## Troubleshooting

- **Plugins not working?** Make sure TPM is installed and you've run `Ctrl-a I`
- **Prefix key issues?** Check if another app is using Ctrl-a
- **Colors not working?** Ensure your terminal supports true colors
- **Session restore failing?** Check `~/.config/tmux/resurrect/` for save files
- **Mouse not working?** Verify tmux version supports mouse mode 