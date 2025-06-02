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
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# yazi cwd shell wrapper
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

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
    
    # Shared fd command with optimized excludes
    export FZF_FD_COMMAND='fd --type f --hidden --size -5M --exclude .git --exclude node_modules --exclude build --exclude dist --exclude target --exclude vendor --exclude .ollama --exclude .stack --exclude Library --exclude OrbStack --exclude .orbstack --exclude .rustup --exclude .nvm --exclude .DS_Store'
    
    # fzf environment variables
    export FZF_DEFAULT_OPTS='--height 100% --layout=reverse --border'
    export FZF_DEFAULT_COMMAND="$FZF_FD_COMMAND"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_CTRL_T_OPTS='--preview "bat --color=always {}"'
    
    # fzf + nvim alias using shared command
    fv() {
        local file=$(eval $FZF_FD_COMMAND | fzf --preview "bat --color=always {}")
        [[ -n $file ]] && nvim "$file"
    }
fi