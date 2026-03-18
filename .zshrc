[[ $- != *i* ]] && return

export DOTFILES="$HOME/Projects/dotfiles"
export ZSH="$HOME/.oh-my-zsh"

source_if_exists() {
    [[ -s "$1" ]] && . "$1"
}

source_if_exists "$HOME/.profile"
source_if_exists "$HOME/.env"
source_if_exists "$HOME/.env.sh"
source_if_exists "$DOTFILES/.aliases"
source_if_exists "$DOTFILES/.functions"
source_if_exists "$DOTFILES/.path"
