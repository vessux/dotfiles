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

# `dev` — one command to land in the devbox work session and resume it across
# sleeps / network changes. Eternal Terminal (et) holds a re-connectable session
# to etserver and transparently relays the byte stream, so tmux, clipboard, mouse
# and colors all behave like plain ssh; tmux keeps the session alive server-side.
# `new-session -A -s main` attaches to `main` or creates it. et bootstraps over
# ssh, so it reads ~/.ssh/config (Host devbox → User kovis). On the devbox itself
# there's nothing to et into — attach locally; fall back to ssh if et is absent.
dev() {
    if [[ ${HOST%%.*} == devbox ]]; then
        command tmux new-session -A -s main
    elif command -v et &> /dev/null; then
        et --command='tmux new-session -A -s main' devbox
    else
        ssh -t devbox 'tmux new-session -A -s main'
    fi
}

# rbw: the unlock-popup labeling (the ~/Library/Caches/rbw-touchid-ctx "sticky
# note" pinentry-rbw-touchid reads) and the post-fetch re-lock used to live here
# as a zsh function. They now live in a wrapper around the rbw binary itself,
# installed via nix-darwin (nix/packages.nix → rbw-touchid), so every caller —
# scripts, ansible, cron — is covered, not just this interactive shell.

# zoxide smart cd command
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
export PATH="$PATH:${XDG_DATA_HOME}/npm/bin:$HOME/.cache/.bun/bin:$HOME/.local/bin"

# Umbel shim for claude
export PATH="${XDG_DATA_HOME}/umbel/bin:$PATH"

# mise — runtime/tool version manager (node, just, …). Activated last so its shims
# take PATH precedence; guarded so it's a no-op where mise isn't installed. Does
# nothing until a global (~/.config/mise) or project (.mise.toml) config declares a tool.
# ~/.config/mise is a stow dir-symlink → ~/dotfiles/mise, so mise resolves the global
# config to a path outside ~/.config and refuses to trust it. Trust ~/dotfiles up front
# so it's silent on every box without a manual `mise trust` per machine.
export MISE_TRUSTED_CONFIG_PATHS="${HOME}/dotfiles"
command -v mise >/dev/null && eval "$(mise activate zsh)"

# ~/.config/bin — re-prepended LAST so it wins interactively too. .zshenv already puts it on
# PATH (for non-interactive callers, same reason as the mise shims), but an interactive shell
# then rebuilds PATH with the system defaults — /usr/local/bin et al. — and the tool managers
# above (mise, cargo) ahead of it, dropping ~/.config/bin behind /usr/local/bin. That SHADOWS
# the `bd` shim (~/.config/bin/bd) behind the real /usr/local/bin/bd, silently defeating the
# private-beads auto-sync (ADR 0013, dotfiles-sp0/zao): with dolt.auto-push off, an unshadowed
# shim is the ONLY thing that pushes captures to the remote. Re-prepending here (after mise,
# the last PATH writer) is the same non-interactive-.zshenv / interactive-.zshrc split mise
# uses above. The three scripts here (bd/clip/plannotate) don't collide with any mise tool.
export PATH="$HOME/.config/bin:$PATH"
