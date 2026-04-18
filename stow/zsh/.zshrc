#!/usr/bin/env zsh

# ── Oh My Zsh ────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""  # Using starship instead

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

if [[ -d "$ZSH/custom/plugins/zsh-completions" ]]; then
    plugins+=(zsh-completions)
    [[ -d "$ZSH/custom/plugins/zsh-completions/src" ]] && \
        fpath+="$ZSH/custom/plugins/zsh-completions/src"
fi

source "$ZSH/oh-my-zsh.sh"

# ── Custom config ─────────────────────────────────────────────
if [[ -z "${DOTFILES:-}" ]]; then
    # ${(%):-%N} expands to the path of the currently sourced file in zsh
    local zshrc_path=${(%):-%N}
    if [[ -n "$zshrc_path" ]]; then
        DOTFILES="${zshrc_path:A:h:h:h}" # stow/zsh/.zshrc -> dotfiles root
    else
        DOTFILES="$HOME/Projects/dotfiles"
    fi
fi
export DOTFILES

source_if_exists() {
    [[ -s "$1" ]] && . "$1"
}

source_if_exists "$HOME/.env"
source_if_exists "$HOME/.env.sh"
source_if_exists "$HOME/.path"
source_if_exists "$HOME/.aliases"
source_if_exists "$HOME/.functions"

# Source all scripts in snippets directory
if [[ -d "$DOTFILES/snippets" ]]; then
    for snippet in "$DOTFILES"/snippets/*.sh; do
        [[ -r "$snippet" ]] && source "$snippet"
    done
fi

export PATH=$PATH:/home/kayaman/.local/bin

# ── Starship prompt ───────────────────────────────────────────
command -v starship &>/dev/null && eval "$(starship init zsh)"
export GPG_TTY=$(tty)

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/kayaman/google-cloud-sdk/path.zsh.inc' ]; then . '/home/kayaman/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/kayaman/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/kayaman/google-cloud-sdk/completion.zsh.inc'; fi
export PATH="$HOME/development/flutter/bin:$PATH"
