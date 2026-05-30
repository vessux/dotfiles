# If the terminal's terminfo isn't installed on this host (e.g. xterm-ghostty on
# a fresh remote), fall back to a universally-available TERM. Must run before
# compinit/ZLE so key bindings (backspace!) resolve, and before launching tmux.
# Truecolor is unaffected (driven by $COLORTERM, which Ghostty still sets).
if ! infocmp "$TERM" &>/dev/null; then
    export TERM=xterm-256color
fi

# completion
if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
  FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"
fi
autoload -Uz compinit
() {
  setopt local_options extended_glob
  local zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
  if [[ -n $zcompdump(#qN.mh-24) ]]; then
    compinit -C -d "$zcompdump"
  else
    compinit -d "$zcompdump"
  fi
}
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

alias d='docker'
alias dc='docker compose'
alias authagent='eval `ssh-agent -s` && ssh-add /Users/kovis/.ssh/id_rsa && ssh-add /Users/kovis/.ssh/jakub.koval'
alias primavpn='sudo openfortivpn -c ~/.ssh/fortiprimaconfig'
alias nixapply='sudo darwin-rebuild switch --flake ~/.config/nix'

# Dirs
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."

# neovim
export EDITOR=nvim
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# claude code
alias cl='claude'
alias clusage='npx ccusage@latest'
alias mute-claude='touch ${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/notify-silent'
alias unmute-claude='rm -f ${XDG_CONFIG_HOME:-$HOME/.config}/claude-code/notify-silent'

# npm
export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/.npmrc
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node_repl/history"

# Local secrets (untracked): tokens/keys referenced by configs, e.g. $NPM_TOKEN in .npmrc
[[ -f ${ZDOTDIR:-$HOME}/.zsh_secrets ]] && source ${ZDOTDIR:-$HOME}/.zsh_secrets

# yazi cwd shell wrapper
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# Eza
alias l="eza -l --icons --git -a"
alias lt="eza --tree --level=2 --long --icons --git"
alias ltree="eza --tree --level=2  --icons --git"

lg()
{
    export LAZYGIT_NEW_DIR_FILE=~/.lazygit/newdir

    lazygit "$@"

    if [ -f $LAZYGIT_NEW_DIR_FILE ]; then
            cd "$(cat $LAZYGIT_NEW_DIR_FILE)"
            rm -f $LAZYGIT_NEW_DIR_FILE > /dev/null
    fi
}

# fzf configuration
if command -v fzf &> /dev/null; then
    # Source fzf key bindings and completion
    source <(fzf --zsh)
    
    # Shared fd excludes function
    _fd_excludes() {
        echo "--exclude .git --exclude node_modules --exclude build --exclude dist --exclude target --exclude vendor --exclude .ollama --exclude .stack --exclude Library --exclude OrbStack --exclude .orbstack --exclude .rustup --exclude .nvm --exclude .DS_Store"
    }
    
    # Shared fd command with optimized excludes
    export FZF_FD_COMMAND="fd --type f --hidden --size -5M $(_fd_excludes)"
    
    # fzf environment variables
    export FZF_DEFAULT_OPTS='--height 100% --layout=reverse --border'
    export FZF_DEFAULT_COMMAND="$FZF_FD_COMMAND"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_CTRL_T_OPTS='--preview "bat --color=always {}"'
    
    # fzf + nvim alias using shared command
    fv() {
        local file=$(fd --type f --hidden --size -5M $(_fd_excludes) | fzf --preview "bat --color=always {}")
        [[ -n $file ]] && nvim "$file"
    }
    
    # fzf + file/directory navigation functions using fd
    fcd() { 
        local dir=$(fd --type d --hidden $(_fd_excludes) | fzf)
        [[ -n $dir ]] && cd "$dir" && l
    }
    f() {
        local file=$(fd --type f --hidden --size -5M $(_fd_excludes) | fzf)
        [[ -n $file ]] && echo "$file" | (command -v pbcopy >/dev/null && pbcopy || xclip -selection clipboard 2>/dev/null)
    }
fi

# atuin configuration
if command -v atuin &> /dev/null; then
    eval "$(atuin init zsh)"
fi

# ── Per-host theming ─────────────────────────────────────────────────────────
# The local Mac runs Ghostty in Catppuccin Mocha. Ghostty can't react to which
# host an SSH session lands on, so on remote (SSH) sessions the shell, tmux and
# nvim switch to Macchiato — and we repaint the terminal via OSC — to make
# "am I local or on a devbox?" obvious at a glance.
if [[ -n $SSH_CONNECTION ]]; then
    export TTY_FLAVOR=berry
else
    export TTY_FLAVOR=mocha
fi

# starship: reuse the tracked Mocha config locally; for remote sessions generate
# a copy with just the palette line swapped to the wine "berry" palette (both
# palettes are defined in the toml — single source of truth).
if command -v starship &> /dev/null; then
    if [[ $TTY_FLAVOR == berry ]]; then
        _starship_gen="${XDG_CACHE_HOME:-$HOME/.cache}/starship/berry.toml"
        mkdir -p "${_starship_gen:h}"
        sed "s/^palette = .*/palette = 'berry'/" \
            ~/.config/starship/starship.toml > "$_starship_gen"
        export STARSHIP_CONFIG="$_starship_gen"
    else
        export STARSHIP_CONFIG=~/.config/starship/starship.toml
    fi
    eval "$(starship init zsh)"
fi

# Repaint the terminal to the Berry wine canvas on remote sessions so the host
# is obvious even when the prompt is off-screen. Runs inside tmux too (wrapped in
# passthrough, which needs `allow-passthrough on` — already set).
if [[ $TTY_FLAVOR == berry && -t 1 ]]; then
    _tty_osc() {  # $1 = OSC body, e.g. '11;#331824'; wrap for tmux if needed
        if [[ -n $TMUX ]]; then
            printf '\ePtmux;\e\e]%s\a\e\\' "$1"
        else
            printf '\e]%s\a' "$1"
        fi
    }
    _tty_osc '11;#331824'   # background — wine
    _tty_osc '10;#f7dbe6'   # foreground — light
    _tty_osc '12;#ff5fa2'   # cursor — hot-pink
    # Reset only from the outermost (non-tmux) shell. The terminal background is a
    # single shared resource (the one Ghostty window), but every tmux pane runs
    # its own zsh. If each pane reset on exit, closing one window would repaint the
    # whole terminal back to the Mac default while sibling panes stay open. Gating
    # on -z $TMUX means the reset fires once — when the SSH login shell that owns
    # the real PTY logs out — not on every pane/window close.
    if [[ -z $TMUX ]]; then
        autoload -Uz add-zsh-hook
        _reset_tty_theme() { local s; for s in '111;' '110;' '112;'; do _tty_osc "$s"; done }
        add-zsh-hook zshexit _reset_tty_theme
    fi
fi

# tmux smart session management
if command -v tmux &> /dev/null; then
    source ~/.config/tmux/shell-integration.sh
fi

# rbw: this wrapper does two things on every invocation.
#
# (1) Record the subcommand in a temp file that pinentry-rbw-touchid reads to
#     label the Touch ID popup ("Unlock rbw vault — rbw get github" instead of a
#     bare "Unlock rbw vault"). Any subcommand can trigger an unlock — add and
#     edit just as much as get — so write it for all of them. Remove it after so
#     a later implicit unlock (idle resync) can't reuse a stale label. The path
#     is anchored at $HOME (not $TMPDIR): the rbw-agent that spawns the pinentry
#     is launchd-spawned and a tmux server can carry a stale TMPDIR, so the two
#     could disagree on a $TMPDIR path — $HOME never differs.
#
# (2) Re-lock the agent immediately after every secret-fetching command so the
#     decrypted master keys don't sit in agent RAM between operations. The price
#     is one Touch ID per fetch; the win is that nothing running as me can pull
#     the whole vault by talking to the socket between my own calls. lock_timeout=1
#     (set declaratively in flake.nix) handles the idle-after-implicit-unlock
#     case; this handles the explicit-after-fetch case. Only get / code return
#     secrets, so only they are re-locked.
if command -v rbw &> /dev/null; then
    rbw() {
        local ctx="$HOME/Library/Caches/rbw-touchid-ctx"
        print -r -- "$*" > "$ctx" 2>/dev/null
        command rbw "$@"; local ec=$?
        [[ "$1" == (get|code) ]] && command rbw lock >/dev/null 2>&1
        rm -f "$ctx" 2>/dev/null
        return $ec
    }
fi

# zoxide smart cd command
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
export PATH="$PATH:${XDG_DATA_HOME}/npm/bin:$HOME/.cache/.bun/bin:$HOME/.local/bin"
