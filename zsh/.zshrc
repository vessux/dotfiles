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
    export TTY_FLAVOR=macchiato
else
    export TTY_FLAVOR=mocha
fi

# starship: reuse the tracked Mocha config locally; for remote sessions generate
# a copy with just the palette line swapped (all flavors are defined in the toml).
if command -v starship &> /dev/null; then
    if [[ $TTY_FLAVOR == macchiato ]]; then
        _starship_gen="${XDG_CACHE_HOME:-$HOME/.cache}/starship/macchiato.toml"
        mkdir -p "${_starship_gen:h}"
        sed "s/^palette = .*/palette = 'catppuccin_macchiato'/" \
            ~/.config/starship/starship.toml > "$_starship_gen"
        export STARSHIP_CONFIG="$_starship_gen"
    else
        export STARSHIP_CONFIG=~/.config/starship/starship.toml
    fi
    eval "$(starship init zsh)"
fi

# Repaint the terminal (bg/fg/cursor) to Macchiato on remote sessions, reset on
# exit. Skipped inside tmux, where the status bar already carries the signal.
if [[ $TTY_FLAVOR == macchiato && -z $TMUX && -t 1 ]]; then
    printf '\e]11;#24273a\a\e]10;#cad3f5\a\e]12;#f4dbd6\a'
    autoload -Uz add-zsh-hook
    _reset_tty_theme() { printf '\e]111;\a\e]110;\a\e]112;\a' }
    add-zsh-hook zshexit _reset_tty_theme
fi

# tmux smart session management
if command -v tmux &> /dev/null; then
    source ~/.config/tmux/shell-integration.sh
fi

# zoxide smart cd command
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
export PATH="$PATH:${XDG_DATA_HOME}/npm/bin:$HOME/.cache/.bun/bin:$HOME/.local/bin"
