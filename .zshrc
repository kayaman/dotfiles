#!/usr/bin/env zsh

# ── Oh My Zsh ────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""  # Using starship instead

plugins=(
    git
    fzf
    docker
    kubectl
    npm
    python
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
)

# zsh-completions must be in fpath before oh-my-zsh is loaded
[[ -d "$ZSH/custom/plugins/zsh-completions/src" ]] && \
    fpath+="$ZSH/custom/plugins/zsh-completions/src"

source "$ZSH/oh-my-zsh.sh"

# ── Custom config ─────────────────────────────────────────────
DOTFILES="$HOME/Projects/dotfiles"

source_if_exists() {
    [[ -s "$1" ]] && . "$1"
}

source_if_exists "$HOME/.env"
source_if_exists "$HOME/.env.sh"
source_if_exists "$HOME/.aliases"
source_if_exists "$HOME/.functions"

# ── Starship prompt ───────────────────────────────────────────
command -v starship &>/dev/null && eval "$(starship init zsh)"
