#!/usr/bin/env zsh

# ── Profiling Infrastructure ─────────────────────────────────
# Activated by: ZSH_PROF=1 zsh   or   dot profiler
# Writes structured timing data to $ZSH_PROF_LOG (tab-separated).
# Wraps source/. to auto-instrument every sourced file.
if [[ -n "$ZSH_PROF" ]]; then
    zmodload zsh/datetime
    zsh_start_time=$EPOCHREALTIME
    zsh_last_time=$zsh_start_time
    : "${ZSH_PROF_LOG:=/tmp/zsh-profile-$$.log}"
    export ZSH_PROF_LOG
    : > "$ZSH_PROF_LOG"

    log_step() {
        local now=$EPOCHREALTIME
        local delta=$(( (now - zsh_last_time) * 1000 ))
        local elapsed=$(( (now - zsh_start_time) * 1000 ))
        printf "%0.2f\t%0.2f\t%s\n" "$elapsed" "$delta" "$1" >> "$ZSH_PROF_LOG"
        zsh_last_time=$now
    }

    # Wrap source/. to auto-log every sourced file
    _prof_source() {
        local _pf="$1"
        local _pl="${_pf/$HOME/~}"
        log_step "source:begin $_pl"
        builtin source "$@"
        local _rc=$?
        log_step "source:end   $_pl"
        return $_rc
    }
    alias source='_prof_source'
    alias .='_prof_source'
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

# ── Starship prompt (Removed) ─────────────────────────────────
[[ -t 0 ]] && export GPG_TTY=$(tty)

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
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

log_step "Flutter"
_add_to_path "$HOME/development/flutter/bin"

log_step "Finished .zshrc"

# ── Profiling Cleanup ─────────────────────────────────────────
if [[ -n "$ZSH_PROF" ]]; then
    unalias source 2>/dev/null
    unalias . 2>/dev/null
fi

# ── Bun ───────────────────────────────────────────────────────
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
