[[ $- != *i* ]] && return

# Allow DOTFILES to be provided by the environment; otherwise, derive it
# from the location of this sourced .zshrc (handles clones/symlinks).
if [[ -z "${DOTFILES:-}" ]]; then
    zshrc_source=${${(%):-%N}:A}
    DOTFILES=${zshrc_source:h}
fi
export DOTFILES
export ZSH="$HOME/.oh-my-zsh"

source_if_exists() {
    [[ -s "$1" ]] && . "$1"
}

if [[ -o login ]]; then
    source_if_exists "$HOME/.profile"
fi
source_if_exists "$HOME/.env"
source_if_exists "$HOME/.env.sh"
source_if_exists "$DOTFILES/.aliases"
source_if_exists "$DOTFILES/.functions"
source_if_exists "$DOTFILES/.path"
