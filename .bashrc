# ─────────────────────────────────────────────────────────────
#  ~/.bashrc — fast, clean bash config with ble.sh
# ─────────────────────────────────────────────────────────────

# Exit early for non-interactive shells
[[ $- != *i* ]] && return

# ── ble.sh early attach ─────────────────────────────────────
# Must load before the rest of .bashrc for full integration
[[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh" ]] && \
    source "${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh" --noattach

# ── Environment ──────────────────────────────────────────────
export EDITOR="vim"
export VISUAL="$EDITOR"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# PATH — deduplicated
_add_to_path() {
    local dir="$1"
    [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]] && PATH="$dir:$PATH"
}
_add_to_path "$HOME/.local/bin"
_add_to_path "$HOME/.cargo/bin"
# Omit ./node_modules/.bin — add in ~/.bash_local per-project if needed (PATH injection risk)
export PATH

# ── History ──────────────────────────────────────────────────
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=ignoreboth:erasedups
export HISTIGNORE="ls:ll:la:cd:pwd:exit:clear:history"
export HISTTIMEFORMAT="%F %T  "

shopt -s histappend       # append, don't overwrite
shopt -s cmdhist          # multi-line commands as one entry

# ── Shell options ────────────────────────────────────────────
shopt -s autocd           # cd into dirs by typing the name
shopt -s cdspell          # fix minor cd typos
shopt -s dirspell         # fix dir name typos in completion
shopt -s checkwinsize     # update LINES/COLUMNS after each cmd
shopt -s globstar         # ** recursive glob
shopt -s dotglob          # include hidden files in glob
shopt -s extglob          # extended pattern matching
shopt -s nocaseglob       # case-insensitive glob

# ── Bash completion ──────────────────────────────────────────
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
elif [[ -f /etc/bash_completion ]]; then
    source /etc/bash_completion
fi

# npm completion
command -v npm &>/dev/null && eval "$(npm completion 2>/dev/null)"

# zoxide (smart cd) — init once at startup; fallback if not installed
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash)"
else
    z() { echo "Install zoxide: sudo zypper install zoxide" >&2; }
fi

# ── fzf ──────────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    # fzf key bindings & completion (location varies by distro)
    for f in \
        /usr/share/fzf/key-bindings.bash \
        /usr/share/fzf/completion.bash \
        /usr/share/bash-completion/completions/fzf \
        /usr/share/doc/fzf/examples/key-bindings.bash \
        /usr/share/doc/fzf/examples/completion.bash \
        "$HOME/.fzf.bash"; do
        [[ -f "$f" ]] && source "$f"
    done

    export FZF_DEFAULT_OPTS="
        --height=40%
        --layout=reverse
        --border=rounded
        --info=inline
        --prompt='❯ '
        --pointer='▶'
        --marker='✓'
        --color=fg:#c0caf5,bg:-1,hl:#bb9af7
        --color=fg+:#c0caf5,bg+:#283457,hl+:#7dcfff
        --color=info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7
        --color=marker:#9ece6a,spinner:#bb9af7,header:#7aa2f7
        --bind='ctrl-d:half-page-down,ctrl-u:half-page-up'
    "

    # Use fd if available (respects .gitignore)
    if command -v fd &>/dev/null; then
        export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
    fi
fi

# ── Tool configs ─────────────────────────────────────────────

# bat — better cat
export BAT_THEME="TwoDark"
export BAT_STYLE="numbers,changes"

# ripgrep config (only if file exists)
[[ -f "$XDG_CONFIG_HOME/ripgrep/config" ]] && export RIPGREP_CONFIG_PATH="$XDG_CONFIG_HOME/ripgrep/config"

# Python — no __pycache__ clutter in project dirs
export PYTHONDONTWRITEBYTECODE=1

# ── Source modular configs ───────────────────────────────────
[[ -f "$HOME/.bash_aliases" ]]   && source "$HOME/.bash_aliases"
[[ -f "$HOME/.bash_functions" ]] && source "$HOME/.bash_functions"
[[ -f "$HOME/.bash_local" ]]     && source "$HOME/.bash_local"  # machine-specific overrides

# ── Starship prompt ──────────────────────────────────────────
if command -v starship &>/dev/null; then
    eval "$(starship init bash)"
fi

# ── ble.sh late attach ──────────────────────────────────────
# Attach after everything else is loaded
[[ ${BLE_VERSION-} ]] && ble-attach
