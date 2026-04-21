#!/usr/bin/env zsh

# ── Profiling Infrastructure ─────────────────────────────────
if [[ -n "$ZSH_PROF" ]]; then
    zmodload zsh/datetime
    zsh_start_time=$EPOCHREALTIME
    zsh_last_time=$zsh_start_time
    log_step() {
        local now=$EPOCHREALTIME
        local elapsed=$(( now - zsh_start_time ))
        local delta=$(( now - zsh_last_time ))
        printf ">> %0.4fs (+%0.4fs) %s\n" $elapsed $delta "$1"
        zsh_last_time=$now
    }
else
    log_step() { :; }
fi

log_step "Starting .zshrc"

# ── Oh My Zsh ────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="bira"

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

log_step "Loading Oh My Zsh"
source "$ZSH/oh-my-zsh.sh"
log_step "Oh My Zsh loaded"

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

log_step "Sourcing env/aliases/functions"
source_if_exists "$HOME/.env"
source_if_exists "$HOME/.env.sh"
source_if_exists "$HOME/.path"
source_if_exists "$HOME/.aliases"
source_if_exists "$HOME/.functions"

# Source all scripts in snippets directory
if [[ -d "$DOTFILES/snippets" ]]; then
    log_step "Sourcing snippets"
    for snippet in "$DOTFILES"/snippets/*.sh; do
        [[ -r "$snippet" ]] && source "$snippet"
    done
fi

export PATH=$PATH:/home/kayaman/.local/bin

# ── Starship prompt (Removed) ─────────────────────────────────
export GPG_TTY=$(tty)

# ── NVM (Lazy Load Optimization) ──────────────────────────────
log_step "NVM setup (lazy)"
export NVM_DIR="$HOME/.config/nvm"
load_nvm() {
    log_step "Loading NVM (first use)"
    unset -f nvm node npm npx
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { load_nvm; nvm "$@"; }
node() { load_nvm; node "$@"; }
npm()  { load_nvm; npm "$@"; }
npx()  { load_nvm; npx "$@"; }

# ── External Tools ────────────────────────────────────────────
# The next line updates PATH for the Google Cloud SDK.
log_step "GCloud SDK"
if [ -f '/home/kayaman/google-cloud-sdk/path.zsh.inc' ]; then . '/home/kayaman/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/kayaman/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/kayaman/google-cloud-sdk/completion.zsh.inc'; fi

log_step "Flutter"
export PATH="$HOME/development/flutter/bin:$PATH"

log_step "Finished .zshrc"
