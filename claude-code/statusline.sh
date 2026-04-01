#!/bin/bash

# Read Claude Code context
input=$(cat)
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model_id=$(echo "$input" | jq -r '.model.id // empty')

# Catppuccin Mocha colors
RED=$'\033[38;2;243;139;168m'
PEACH=$'\033[38;2;250;179;135m'
YELLOW=$'\033[38;2;249;226;175m'
GREEN=$'\033[38;2;166;227;161m'
SAPPHIRE=$'\033[38;2;116;199;236m'
LAVENDER=$'\033[38;2;180;190;254m'
CRUST=$'\033[38;2;17;17;27m'
TEXT=$'\033[38;2;205;214;244m'
SURFACE0=$'\033[38;2;49;50;68m'
RESET=$'\033[0m'

# Background colors
BG_RED=$'\033[48;2;243;139;168m'
BG_PEACH=$'\033[48;2;250;179;135m'
BG_YELLOW=$'\033[48;2;249;226;175m'
BG_GREEN=$'\033[48;2;166;227;161m'
BG_SAPPHIRE=$'\033[48;2;116;199;236m'
BG_LAVENDER=$'\033[48;2;180;190;254m'

# Get username
username=$(whoami)

# Get abbreviated directory path with icons
dir_name=$(basename "$current_dir")
parent_dir=$(dirname "$current_dir")

# Apply directory icons like starship
case "$dir_name" in
Documents) dir_icon="󰈙 " ;;
Downloads) dir_icon=" " ;;
Music) dir_icon="󰝚 " ;;
Pictures) dir_icon=" " ;;
Developer) dir_icon="󰲋 " ;;
*) dir_icon="" ;;
esac

# Smart truncation for directory
if [[ ${#current_dir} -gt 40 ]]; then
  # Get last 2 directories
  parent_base=$(basename "$parent_dir")
  if [[ "$parent_base" == "/" ]]; then
    abbreviated_dir="$dir_icon$dir_name"
  else
    abbreviated_dir="…/$parent_base/$dir_icon$dir_name"
  fi
else
  abbreviated_dir="$dir_icon$current_dir"
fi

# Get git status if in a git repo
git_info=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null || echo "detached")

  # Git status indicators
  status_indicators=""
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    # Check for different types of changes
    staged_count=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    modified_count=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    untracked_count=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    if [[ $staged_count -gt 0 ]]; then
      status_indicators="${status_indicators}+${staged_count}"
    fi
    if [[ $modified_count -gt 0 ]]; then
      [[ -n $status_indicators ]] && status_indicators="${status_indicators} "
      status_indicators="${status_indicators}!${modified_count}"
    fi
    if [[ $untracked_count -gt 0 ]]; then
      [[ -n $status_indicators ]] && status_indicators="${status_indicators} "
      status_indicators="${status_indicators}?${untracked_count}"
    fi
  fi

  git_info="${YELLOW}${BG_YELLOW}${CRUST}  $branch"
  if [[ -n $status_indicators ]]; then
    git_info="$git_info $status_indicators"
  fi
  git_info="$git_info ${RESET}"
fi

# Format model info if available - extract just the model name
if [[ -n $model_id ]]; then
  # Extract model name (e.g., "claude-3-5-sonnet" from "claude-3-5-sonnet-20241022")
  model_name=$(echo "$model_id" | sed -E 's/-[0-9]{8}$//' | sed 's/claude-//')
  model_info="${LAVENDER}${BG_LAVENDER}${CRUST} 󰚩 $model_name ${RESET}"
else
  model_info=""
fi

# Build the statusline with powerline-style segments and separators
output=""

# OS and username segment (starting separator in red, no background)
output="${RESET}${RED}${BG_RED}${CRUST}󰀵 ${username} ${RESET}"

# Directory segment with separator (separator: red fg on peach bg)
output="${output}${RED}${BG_PEACH}${PEACH}${BG_PEACH}${CRUST} ${abbreviated_dir} ${RESET}"

# Git segment (if in repo) with separator
if [[ -n $git_info ]]; then
  # Separator from directory to git (peach fg on yellow bg)
  output="${output}${PEACH}${BG_YELLOW}${YELLOW}${BG_YELLOW}${CRUST}  ${branch}"
  if [[ -n $status_indicators ]]; then
    output="${output} ${status_indicators}"
  fi
  output="${output} ${RESET}"
  has_git="true"
else
  has_git="false"
fi

# Model segment (if available) with separator
if [[ -n $model_id ]]; then
  if [[ $has_git == "true" ]]; then
    # Separator from git to model (yellow fg on lavender bg)
    output="${output}${YELLOW}${BG_LAVENDER}${LAVENDER}${BG_LAVENDER}${CRUST} 󰚩 ${model_name} ${RESET}"
  else
    # Separator from directory to model (peach fg on lavender bg)
    output="${output}${PEACH}${BG_LAVENDER}${LAVENDER}${BG_LAVENDER}${CRUST} 󰚩 ${model_name} ${RESET}"
  fi
  # End separator (lavender fg, no bg)
  output="${output}${LAVENDER}${RESET}"
else
  if [[ $has_git == "true" ]]; then
    # End separator from git (yellow fg, no bg)
    output="${output}${YELLOW}${RESET}"
  else
    # End separator from directory (peach fg, no bg)
    output="${output}${PEACH}${RESET}"
  fi
fi

printf "%s" "$output"
