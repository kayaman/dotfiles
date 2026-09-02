#!/usr/bin/env zsh
# Git helpers used interactively. (See also: `dot` for dotfiles-repo helpers.)

# Interactive branch switch with fzf
gbf() {
  local branch
  branch="$(git branch --all --sort=-committerdate \
    | sed 's/^[* ]*//' | sed 's|remotes/origin/||' | sort -u \
    | fzf --preview 'git log --oneline --graph --color=always {} -- | head -20')" \
    && git switch "$branch"
}

# Quick commit-all with optional message (default: "wip")
gq() { git add -A && git commit -m "${*:-wip}"; }

# Interactive git add with preview (handles spaces in filenames)
gaf() {
  local files f
  files="$(git diff --name-only --diff-filter=ACMR \
    | fzf --multi --preview 'git diff --color=always -- {}')"
  [[ -z "$files" ]] && return
  while IFS= read -r f; do [[ -n "$f" ]] && git add "$f"; done <<< "$files"
  git status -sb
}

# Compact commit-history graph
ghist() { git log --oneline --graph --decorate -"${1:-15}"; }

# Create branch and switch to it
gbc() {
  git branch "$1" && git checkout "$1"
}

# Fetch + pull
gfp() {
  git fetch && git pull
}
