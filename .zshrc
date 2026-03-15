#!/usr/bin/env zsh

DOTFILES="$HOME/Projects/dotfiles"

source_if_exists() {
    [[ -s "$1" ]] && . "$1"
}

source_if_exists "$HOME/.env"
source_if_exists "$HOME/.env.sh"
source_if_exists "$DOTFILES/.aliases"
source_if_exists "$DOTFILES/.functions"
