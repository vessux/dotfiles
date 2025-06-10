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

**⚙️ Quality of Life:**
- **tmux-sensible**: Sensible defaults that just work

## Pro Tips

1. **Catppuccin Aesthetics**: Active panes glow purple, status bar uses pink/blue highlights
2. **Auto-Restore**: Sessions automatically restore on tmux start - never lose work again
3. **Workflow**: Create one session per project, multiple windows per session
4. **Plugin Management**: `Ctrl-a I` to install, `Ctrl-a U` to update plugins
5. **Fuzzy Navigation**: `Ctrl-a f` for window finder, `Ctrl-a Ctrl-f` for session finder
6. **Search Power**: Use `/` to search text, `Ctrl-f` for files, `Ctrl-u` for URLs

## Common Workflows

### Development Setup
```bash
tmux new -s project
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