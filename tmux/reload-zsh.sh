#!/bin/sh

# Re-init zsh in every tmux pane that's sitting at a shell prompt.
#
# Bound to `prefix + R` in tmux.conf — the companion to `prefix + r`, which
# reloads tmux.conf itself. `exec zsh` replaces each shell with a fresh one that
# re-reads $ZDOTDIR/.zshrc, just like opening a new pane: a clean reload with no
# PATH growth or plugin-init warnings, at the cost of in-shell state (dirstack,
# background jobs).
#
# The -f filter keeps only panes whose foreground command is the shell, so we
# never inject keystrokes into an editor, REPL, or other running program (e.g.
# the node-backed panes a TUI might run in).
tmux list-panes -a -f '#{==:#{pane_current_command},zsh}' -F '#{pane_id}' \
  | while IFS= read -r pane; do
      tmux send-keys -t "$pane" 'exec zsh' Enter
    done
