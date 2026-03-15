#!/usr/bin/env bash
# =============================================================================
#  Bootstrap script for openSUSE Tumbleweed (GNOME) development setup
#
#  Shell:      Bash + bash-it framework + Starship prompt
#  Extras:     fzf, thefuck
#  Editors:    VS Code, Cursor
#  Languages:  nvm (Node), pyenv (Python), rustup (Rust), rbenv (Ruby)
#  Containers: Podman + Buildah + Distrobox, Docker
#
#  Usage:
#    chmod +x bootstrap-tumbleweed.sh
#    ./bootstrap-tumbleweed.sh
# =============================================================================

set -euo pipefail

zypper_install() {
    sudo zypper --non-interactive --no-confirm --auto-agree-with-licenses in "$@"
}

# =============================================================================
#  CONFIGURATION — toggle features on/off (true/false)
# =============================================================================

INSTALL_SYSTEM_UPDATE=true       # Run zypper dup before everything else

# Shell & terminal
INSTALL_BASH_IT=true             # bash-it — framework for bash config, aliases, plugins
INSTALL_STARSHIP=true            # Starship cross-shell prompt
INSTALL_TMUX=true                # tmux terminal multiplexer
INSTALL_FZF=true                 # fzf — fuzzy finder (Ctrl+R history, Ctrl+T files, Alt+C dirs)
INSTALL_THEFUCK=true             # thefuck — auto-correct mistyped commands

# Base tools
INSTALL_BASE_TOOLS=true          # gcc, make, cmake, git, curl, ripgrep, bat, etc.

# Editors
INSTALL_VSCODE=true              # Visual Studio Code (Microsoft repo)
INSTALL_CURSOR=true              # Cursor AI editor (AppImage)
INSTALL_NEOVIM=false             # Neovim
INSTALL_JETBRAINS_TOOLBOX=false  # JetBrains Toolbox

# Language managers
INSTALL_NVM=true                 # nvm — Node Version Manager
INSTALL_PYENV=true               # pyenv — Python version manager
INSTALL_RUSTUP=true              # rustup — Rust toolchain manager
INSTALL_RBENV=true               # rbenv — Ruby version manager

# Containers
INSTALL_PODMAN=true              # Podman + Buildah + Distrobox
INSTALL_DOCKER=true              # Docker Engine

# GNOME extras
INSTALL_GNOME_EXTRAS=true        # gnome-tweaks, gnome-browser-connector, seahorse
INSTALL_FLATPAK_FLATHUB=true     # Enable Flathub remote

# Fonts
INSTALL_FONTS=true               # JetBrains Mono + Fira Code + Nerd Font variant

# Snapper snapshot before starting
CREATE_SNAPSHOT=true             # Btrfs/Snapper snapshot before changes

# =============================================================================
#  HELPERS
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${RESET}"; }

has_cmd() { command -v "$1" &>/dev/null; }

BASHRC="$HOME/.bashrc"
BASH_LOCAL="$HOME/.bash_local"

append_if_missing() {
    local line="$1"

    # If ~/.bashrc is a symlink (e.g., to a repo-tracked bash/.bashrc),
    # write machine-specific overrides to ~/.bash_local instead.
    local target="$BASHRC"
    if [[ -L "$BASHRC" ]]; then
        target="$BASH_LOCAL"
        [[ -f "$target" ]] || touch "$target"
    fi

    grep -qF "$line" "$target" || echo "$line" >> "$target"
}

# =============================================================================
#  PRE-FLIGHT CHECKS
# =============================================================================

if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root. It will use sudo where needed."
    exit 1
fi

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║   openSUSE Tumbleweed — Developer Bootstrap             ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

if ! grep -q "Tumbleweed" /etc/os-release 2>/dev/null; then
    warn "This doesn't look like openSUSE Tumbleweed. Continue anyway? [y/N] "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

# Ensure ~/.local/bin is on PATH for this session
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Ensure ~/.bashrc exists
touch "$BASHRC"

# =============================================================================
#  SNAPSHOT
# =============================================================================

if $CREATE_SNAPSHOT; then
    section "Btrfs Snapshot"
    if has_cmd snapper; then
        sudo snapper create --description "pre-bootstrap-$(date +%F)"
        success "Snapshot created."
    else
        warn "snapper not found — skipping snapshot."
    fi
fi

# =============================================================================
#  SYSTEM UPDATE
# =============================================================================

if $INSTALL_SYSTEM_UPDATE; then
    section "System Update (zypper dup)"
    sudo zypper --non-interactive dup --auto-agree-with-licenses
    success "System is up to date."
fi


# =============================================================================
#  BASE DEVELOPMENT TOOLS
# =============================================================================

if $INSTALL_BASE_TOOLS; then
    section "Base Development Tools"
    zypper_install -t pattern devel_basis
    zypper_install \
        git git-lfs \
        curl wget \
        make cmake ninja \
        gcc gcc-c++ \
        clang llvm \
        jq \
        ripgrep fd bat \
        htop \
        unzip zip \
        openssl openssl-devel \
        readline-devel \
        sqlite3-devel \
        libffi-devel \
        xz-devel \
        libuuid-devel \
        libyaml-devel \
        pkg-config
    success "Base tools installed."
fi

# =============================================================================
#  BASH-IT
# =============================================================================

if $INSTALL_BASH_IT; then
    section "bash-it — Bash Framework"

    if [[ -d "$HOME/.bash_it" ]]; then
        info "bash-it already installed."
    else
        git clone --depth=1 https://github.com/Bash-it/bash-it.git "$HOME/.bash_it"
        # Install silently (--no-modify-rcfiles lets us control .bashrc ourselves)
        "$HOME/.bash_it/install.sh" --silent --no-modify-rcfiles
        success "bash-it installed."
    fi

    # Wire bash-it into .bashrc if not already present
    if ! grep -q 'bash_it.sh' "$BASHRC"; then
        cat >> "$BASHRC" <<'BASHIT'

# ── bash-it ──────────────────────────────────────────────────────────────────
export BASH_IT="$HOME/.bash_it"

# Theme: set to 'pure' or 'powerline-multiline' for a fancy Nerd Font look.
# Set to 'bira' or 'bobby' for a classic look without Nerd Fonts.
# Starship overrides this anyway if INSTALL_STARSHIP=true.
export BASH_IT_THEME='powerline-multiline'

# Don't check mail
unset MAILCHECK

export SCM_CHECK=true           # show git status in prompt
export SHORT_HOSTNAME=$(hostname -s)

source "$BASH_IT/bash_it.sh"
# ─────────────────────────────────────────────────────────────────────────────
BASHIT
        success "bash-it wired into ~/.bashrc."
    else
        info "bash-it already in ~/.bashrc."
    fi

    # Enable a sensible set of plugins, completions, and aliases
    # We source bash_it.sh first so the enable commands work
    export BASH_IT="$HOME/.bash_it"
    # shellcheck source=/dev/null
    source "$BASH_IT/bash_it.sh" 2>/dev/null || true

    bash-it enable alias   general git docker curl \
        2>/dev/null || true
    bash-it enable plugin  base git extract dirs \
        history-substring-search \
        2>/dev/null || true
    bash-it enable completion bash-it git docker \
        2>/dev/null || true

    success "bash-it aliases, plugins, and completions enabled."
    info "Customise further with: bash-it enable/disable <type> <name>"
    info "Browse available items with: bash-it show aliases | plugins | completions"
fi

# =============================================================================
#  TMUX
# =============================================================================

if $INSTALL_TMUX; then
    section "tmux"
    sudo zypper --non-interactive in tmux
    success "tmux installed."
fi

# =============================================================================
#  STARSHIP PROMPT
# =============================================================================
#
#  NOTE: Starship is loaded AFTER bash-it in ~/.bashrc so it overrides
#  bash-it's built-in theme. This is intentional — you get bash-it's
#  completions/aliases/plugins + Starship's beautiful prompt.

if $INSTALL_STARSHIP; then
    section "Starship Prompt"
    if has_cmd starship; then
        info "Starship already installed."
    else
        tmp_starship_installer="$(mktemp)"
        curl -fsSL https://starship.rs/install.sh -o "$tmp_starship_installer"
        sh "$tmp_starship_installer" --yes
        rm -f "$tmp_starship_installer"
        success "Starship installed."
    fi

    # Append after bash-it so Starship wins the PS1 race
    append_if_missing '# ── Starship prompt (overrides bash-it theme) ──────────────────────────────'
    append_if_missing 'eval "$(starship init bash)"'

    # Drop in a good default config if none exists
    mkdir -p "$HOME/.config"
    if [[ ! -f "$HOME/.config/starship.toml" ]]; then
        cat > "$HOME/.config/starship.toml" <<'TOML'
# Starship config — https://starship.rs/config/
# Uses Nerd Font symbols. Set your terminal font to "JetBrainsMono Nerd Font".

"$schema" = 'https://starship.rs/config-schema.json'

format = """
[╭─](bold green)$os$username$hostname$directory$git_branch$git_status$git_state
[╰─](bold green)$character"""

[os]
disabled = false

[username]
show_always = false
format = "[$user]($style)@"
style_user = "bold cyan"

[hostname]
ssh_only = true
format = "[$hostname]($style) "
style = "bold yellow"

[directory]
truncation_length = 4
truncate_to_repo = true
style = "bold blue"

[git_branch]
symbol = " "
style = "bold purple"

[git_status]
conflicted = "⚡"
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
untracked = "?"
stashed = "$"
modified = "!"
staged = "+"
renamed = "»"
deleted = "✘"
style = "bold red"

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"

[nodejs]
symbol = " "

[python]
symbol = " "

[rust]
symbol = " "

[ruby]
symbol = " "

[docker_context]
symbol = " "
TOML
        success "Starship config written to ~/.config/starship.toml"
    else
        info "~/.config/starship.toml already exists — leaving it alone."
    fi
fi

# =============================================================================
#  FZF — Fuzzy Finder
# =============================================================================

if $INSTALL_FZF; then
    section "fzf — Fuzzy Finder"

    if [[ -d "$HOME/.fzf" ]]; then
        info "fzf already installed."
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        "$HOME/.fzf/install" --all --no-update-rc
        success "fzf installed."
    fi

    # Wire fzf into .bashrc
    append_if_missing '# ── fzf ──────────────────────────────────────────────────────────────────────'
    append_if_missing '[[ -f ~/.fzf.bash ]] && source ~/.fzf.bash'

    # fzf options: use bat for previews, fd for file finding if available
    append_if_missing '# fzf settings'
    append_if_missing 'export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --info=inline"'
    append_if_missing '# Use fd for fzf file search (respects .gitignore)'
    append_if_missing 'command -v fd >/dev/null 2>&1 && export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"'
    append_if_missing 'command -v fd >/dev/null 2>&1 && export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"'
    append_if_missing '# Preview files with bat when available'
    append_if_missing 'command -v bat >/dev/null 2>&1 && export FZF_CTRL_T_OPTS="--preview '"'"'bat --color=always --line-range :50 {}'"'"'"'

    success "fzf configured. Key bindings:"
    info "  Ctrl+R  — fuzzy search shell history"
    info "  Ctrl+T  — fuzzy insert file path"
    info "  Alt+C   — fuzzy cd into directory"
fi

# =============================================================================
#  THEFUCK — Auto-correct mistyped commands
# =============================================================================

if $INSTALL_THEFUCK; then
    section "thefuck — Command Auto-Corrector"

    # thefuck requires Python; install via pipx to keep it isolated
    if ! has_cmd pipx; then
        sudo zypper --non-interactive in python3-pipx 2>/dev/null || \
            python3 -m pip install --user pipx
    fi

    if has_cmd thefuck; then
        info "thefuck already installed."
    else
        pipx install thefuck
        success "thefuck installed via pipx."
    fi

    append_if_missing '# ── thefuck ──────────────────────────────────────────────────────────────────'
    append_if_missing '# Type "fuck" after a bad command to auto-correct it.'
    append_if_missing '# Or just press Esc twice.'
    append_if_missing 'command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias)"'
    append_if_missing '# Esc+Esc shortcut (double-escape to trigger correction)'
    append_if_missing 'command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias --enable-experimental-instant-mode)"'

    success "thefuck installed. Type 'fuck' after a bad command to fix it."
fi

# =============================================================================
#  EDITOR — VS CODE
# =============================================================================

if $INSTALL_VSCODE; then
    section "Visual Studio Code"
    if has_cmd code; then
        info "VS Code already installed."
    else
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        if ! sudo zypper repos 2>/dev/null | grep -q vscode; then
            sudo zypper --non-interactive ar \
                https://packages.microsoft.com/yumrepos/vscode vscode
        fi
        sudo zypper --non-interactive refresh
        sudo zypper --non-interactive in code
        success "VS Code installed."
    fi
fi

# =============================================================================
#  EDITOR — CURSOR
# =============================================================================

if $INSTALL_CURSOR; then
    section "Cursor AI Editor"
    CURSOR_APPIMAGE="$HOME/.local/share/cursor/cursor.AppImage"
    CURSOR_BIN="$HOME/.local/bin/cursor"

    mkdir -p "$HOME/.local/share/cursor" "$HOME/.local/bin" \
             "$HOME/.local/share/applications"

    if [[ -f "$CURSOR_APPIMAGE" ]]; then
        info "Cursor AppImage already present."
    else
        info "Downloading Cursor AppImage..."
        curl -fL "https://downloader.cursor.sh/linux/appImage/x64" \
            -o "$CURSOR_APPIMAGE"
        chmod +x "$CURSOR_APPIMAGE"
        success "Cursor AppImage downloaded."
    fi

    if [[ ! -f "$CURSOR_BIN" ]]; then
        cat > "$CURSOR_BIN" <<'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.local/share/cursor/cursor.AppImage" --no-sandbox "$@"
WRAPPER
        chmod +x "$CURSOR_BIN"
        success "cursor command installed to ~/.local/bin/cursor"
    fi

    cat > "$HOME/.local/share/applications/cursor.desktop" <<DESKTOP
[Desktop Entry]
Name=Cursor
Comment=Cursor AI Code Editor
Exec=$HOME/.local/bin/cursor %F
Icon=code
Type=Application
Categories=Development;TextEditor;IDE;
MimeType=text/plain;inode/directory;
StartupNotify=true
StartupWMClass=Cursor
DESKTOP
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    append_if_missing 'export PATH="$HOME/.local/bin:$PATH"'
    success "Cursor installed. Launch with: cursor  or from the GNOME app grid."
fi

# =============================================================================
#  EDITOR — NEOVIM (optional)
# =============================================================================

if $INSTALL_NEOVIM; then
    section "Neovim"
    sudo zypper --non-interactive in neovim
    success "Neovim installed."
fi

# =============================================================================
#  LANGUAGE — NVM (Node.js)
# =============================================================================

if $INSTALL_NVM; then
    section "nvm — Node Version Manager"
    if [[ -d "$HOME/.nvm" ]]; then
        info "nvm already installed."
    else
        NVM_LATEST=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
            | grep '"tag_name"' | cut -d'"' -f4)
        curl -fsSL \
            "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
        success "nvm ${NVM_LATEST} installed."
    fi

    append_if_missing '# ── nvm ──────────────────────────────────────────────────────────────────────'
    append_if_missing 'export NVM_DIR="$HOME/.nvm"'
    append_if_missing '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    append_if_missing '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    nvm alias default "lts/*"
    success "Node.js LTS installed. Run 'nvm install <version>' to add more."
fi

# =============================================================================
#  LANGUAGE — PYENV (Python)
# =============================================================================

if $INSTALL_PYENV; then
    section "pyenv — Python Version Manager"
    if [[ -d "$HOME/.pyenv" ]]; then
        info "pyenv already installed."
    else
        curl -fsSL https://pyenv.run | bash
        success "pyenv installed."
    fi

    append_if_missing '# ── pyenv ────────────────────────────────────────────────────────────────────'
    append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"'
    append_if_missing '[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
    append_if_missing 'eval "$(pyenv init -)"'
    append_if_missing 'eval "$(pyenv virtualenv-init -)"'

    # pipx for isolated global Python CLI tools
    sudo zypper --non-interactive in python3-pipx 2>/dev/null || \
        python3 -m pip install --user pipx 2>/dev/null || true

    success "pyenv installed. Next: pyenv install 3.12 && pyenv global 3.12"
    info "Use pipx for global tools: pipx install black ruff httpie"
fi

# =============================================================================
#  LANGUAGE — RUSTUP (Rust)
# =============================================================================

if $INSTALL_RUSTUP; then
    section "rustup — Rust Toolchain Manager"
    if has_cmd rustup; then
        info "rustup already installed — updating."
        rustup update
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --no-modify-path
        success "Rust stable toolchain installed."
    fi

    append_if_missing '# ── Rust / cargo ─────────────────────────────────────────────────────────────'
    append_if_missing '. "$HOME/.cargo/env"'

    # shellcheck source=/dev/null
    source "$HOME/.cargo/env" 2>/dev/null || true
    rustup component add clippy rustfmt rust-analyzer 2>/dev/null || true
    success "Rust ready — clippy, rustfmt, rust-analyzer added."
fi

# =============================================================================
#  LANGUAGE — RBENV (Ruby)
# =============================================================================

if $INSTALL_RBENV; then
    section "rbenv — Ruby Version Manager"
    sudo zypper --non-interactive in \
        libopenssl-devel libxml2-devel libxslt-devel \
        libyaml-devel libgdbm-devel libffi-devel

    if [[ -d "$HOME/.rbenv" ]]; then
        info "rbenv already installed."
    else
        git clone --depth=1 https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
        git clone --depth=1 https://github.com/rbenv/ruby-build.git \
            "$HOME/.rbenv/plugins/ruby-build"
        success "rbenv + ruby-build installed."
    fi

    append_if_missing '# ── rbenv ────────────────────────────────────────────────────────────────────'
    append_if_missing 'export PATH="$HOME/.rbenv/bin:$PATH"'
    append_if_missing 'eval "$(rbenv init - bash)"'

    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init - bash)" 2>/dev/null || true
    success "rbenv installed. Next: rbenv install 3.3.0 && rbenv global 3.3.0"
fi

# =============================================================================
#  CONTAINERS — PODMAN + BUILDAH + DISTROBOX
# =============================================================================

if $INSTALL_PODMAN; then
    section "Podman + Buildah + Distrobox"
    sudo zypper --non-interactive in podman buildah

    if has_cmd distrobox; then
        info "Distrobox already installed."
    else
        curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install \
            | sh -s -- --prefix "$HOME/.local"
        success "Distrobox installed to ~/.local/bin"
    fi

    append_if_missing 'export PATH="$HOME/.local/bin:$PATH"'
    loginctl enable-linger "$USER" 2>/dev/null || true
    success "Podman, Buildah, and Distrobox ready."
    info "Try: distrobox create --name dev-ubuntu --image ubuntu:24.04"
fi

# =============================================================================
#  CONTAINERS — DOCKER
# =============================================================================

if $INSTALL_DOCKER; then
    section "Docker Engine"
    if has_cmd docker; then
        info "Docker already installed."
    else
        sudo zypper --non-interactive in docker docker-compose
        sudo systemctl enable --now docker
        success "Docker installed and enabled."
    fi

    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        warn "Added $USER to the 'docker' group — log out/in for it to take effect."
    fi

    if $INSTALL_PODMAN; then
        info "Podman (rootless) and Docker (root daemon) both installed and coexist fine."
        info "Tip: export DOCKER_HOST=unix:///run/user/\$(id -u)/podman/podman.sock"
        info "     to point the Docker CLI at Podman instead."
    fi
fi

# =============================================================================
#  GNOME EXTRAS
# =============================================================================

if $INSTALL_GNOME_EXTRAS; then
    section "GNOME Extras"
    sudo zypper --non-interactive in \
        gnome-tweaks \
        gnome-browser-connector \
        seahorse \
        dconf-editor
    success "GNOME extras installed."
    info "Browse extensions at https://extensions.gnome.org"
fi

# =============================================================================
#  FLATPAK + FLATHUB
# =============================================================================

if $INSTALL_FLATPAK_FLATHUB; then
    section "Flatpak + Flathub"
    sudo zypper --non-interactive in flatpak
    if ! flatpak remotes --user 2>/dev/null | grep -q flathub; then
        flatpak remote-add --if-not-exists --user flathub \
            https://flathub.org/repo/flathub.flatpakrepo
        success "Flathub remote added (user-scoped)."
    else
        info "Flathub already configured."
    fi
    info "Install apps with: flatpak install flathub <app-id>"
    info "Picks: com.getpostman.Postman  io.dbeaver.DBeaverCommunity  io.github.flattool.Warehouse"
fi

# =============================================================================
#  FONTS
# =============================================================================

if $INSTALL_FONTS; then
    section "Developer Fonts"
    sudo zypper --non-interactive in jetbrains-mono-fonts fira-code-fonts

    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"

    if [[ ! -f "$FONT_DIR/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
        info "Downloading JetBrains Mono Nerd Font..."
        TMP_ZIP=$(mktemp --suffix=.zip)
        curl -fL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" \
            -o "$TMP_ZIP"
        unzip -q "$TMP_ZIP" -d "$FONT_DIR"
        rm -f "$TMP_ZIP"
        fc-cache -f "$FONT_DIR"
        success "JetBrains Mono Nerd Font installed to $FONT_DIR"
    else
        info "JetBrains Mono Nerd Font already present."
    fi
fi

# =============================================================================
#  DONE
# =============================================================================

echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║   Bootstrap complete! 🎉                                ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

cat <<'NEXTSTEPS'
Next steps:

  Reload your shell to pick up all changes:
    source ~/.bashrc
    (or open a new terminal)

  Log out / log back in to apply:
    • docker group membership

  Set your terminal font to "JetBrainsMono Nerd Font" for Starship icons.

  Set up language versions:
    • Node:   nvm install --lts
    • Python: pyenv install 3.12 && pyenv global 3.12
    • Ruby:   rbenv install 3.3.0 && rbenv global 3.3.0
    • Rust:   already on stable  (rustup update anytime)

  bash-it — manage your shell:
    bash-it show   aliases | plugins | completions
    bash-it enable plugin  <name>
    bash-it update

  fzf key bindings (active in every new terminal):
    Ctrl+R   fuzzy search command history
    Ctrl+T   fuzzy insert a file path
    Alt+C    fuzzy cd into a subdirectory

  thefuck:
    $ git comit -m "oops"         # bad command
    $ fuck                        # auto-corrects to: git commit -m "oops"
    (or press Esc twice)

  Starship customisation:
    Edit ~/.config/starship.toml
    Browse presets: https://starship.rs/presets

  Try Distrobox:
    distrobox create --name ubuntu --image ubuntu:24.04
    distrobox enter ubuntu

NEXTSTEPS
