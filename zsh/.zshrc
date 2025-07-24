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

# npm
export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/.npmrc
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node_repl/history"

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
        [[ -n $file ]] && echo "$file" | pbcopy
    }
fi

# atuin configuration
if command -v atuin &> /dev/null; then
    eval "$(atuin init zsh)"
fi

# starship configuration
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
    export STARSHIP_CONFIG=~/.config/starship/starship.toml
fi

# tmux smart session management
if command -v tmux &> /dev/null; then
    source ~/.config/tmux/shell-integration.sh
fi

# zoxide smart cd command
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

export PATH="$PATH:${XDG_DATA_HOME}/npm/bin:$HOME/.local/bin"
