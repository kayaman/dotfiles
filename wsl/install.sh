#!/usr/bin/env bash
# =============================================================================
#  Dotfiles Installer — WSL (Ubuntu/Debian)
#  Installs system packages, dev tools, Oh My Zsh, Starship, and symlinks dotfiles.
# =============================================================================

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${XDG_CONFIG_HOME:="$HOME/.config"}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${NC}"; }

# ── 1. System packages ───────────────────────────────────────
install_system_packages() {
    section "System Packages (WSL)"
    
    sudo apt-get update
    sudo apt-get install -y \
        git curl wget unzip tar build-essential gawk jq \
        fzf bat fd-find ripgrep git-delta htop tmux tree \
        python3 python3-pip python3-venv pipx \
        zsh
    
    # Ubuntu aliases for modern tools
    [[ ! -L /usr/local/bin/bat ]] && [[ -x /usr/bin/batcat ]] && sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
    [[ ! -L /usr/local/bin/fd ]] && [[ -x /usr/bin/fdfind ]] && sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd

    # Install eza
    if ! command -v eza &>/dev/null; then
        sudo mkdir -p /etc/apt/keyrings
        if sudo apt-get install -y gnupg >/dev/null && \
           wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg; then
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
            sudo apt-get update && sudo apt-get install -y eza || { warn "eza install failed"; sudo rm -f /etc/apt/sources.list.d/gierens.list; }
        else
            warn "eza install failed: could not import GPG key"
            sudo rm -f /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        fi
    fi

    ok "System packages installed"
}

# ── 2. Oh My Zsh ─────────────────────────────────────────────
install_oh_my_zsh() {
    section "Oh My Zsh"
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        RUNZSH=no KEEP_ZSHRC=yes bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
        ok "Oh My Zsh installed"
    else
        ok "Oh My Zsh already installed"
    fi

    # Plugins
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    local plugins=(
        "zsh-autosuggestions:https://github.com/zsh-users/zsh-autosuggestions.git"
        "zsh-syntax-highlighting:https://github.com/zsh-users/zsh-syntax-highlighting.git"
        "zsh-completions:https://github.com/zsh-users/zsh-completions.git"
    )

    for plug in "${plugins[@]}"; do
        local name="${plug%%:*}" repo="${plug##*:}"
        local dest="$ZSH_CUSTOM/plugins/$name"
        if [[ ! -d "$dest" ]]; then
            git clone --depth=1 "$repo" "$dest"
            ok "$name plugin installed"
        fi
    done
}

# ── 3. Dev Tools & Managers ──────────────────────────────────
install_dev_tools() {
    section "Development Tools"
    
    # nvm
    if [[ ! -d "$HOME/.nvm" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
        ok "nvm installed"
    else
        ok "nvm already installed"
    fi

    # uv
    if ! command -v uv &>/dev/null && [ ! -f "$HOME/.local/bin/uv" ] && [ ! -f "$HOME/.cargo/bin/uv" ]; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
        ok "uv installed"
    else
        ok "uv already installed"
    fi

    # pyenv
    if [[ ! -d "$HOME/.pyenv" ]]; then
        curl -fsSL https://pyenv.run | bash
        ok "pyenv installed"
    else
        ok "pyenv already installed"
    fi

    # rustup
    if ! command -v rustup &>/dev/null && [ ! -f "$HOME/.cargo/bin/rustup" ]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        ok "rustup installed"
    else
        ok "rustup already installed"
    fi

    # starship
    if ! command -v starship &>/dev/null && [ ! -f "/usr/local/bin/starship" ]; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y
        ok "starship installed"
    else
        ok "starship already installed"
    fi
}

# ── 4. Symlink Dotfiles ──────────────────────────────────────
symlink_dotfiles() {
    section "Symlinking Dotfiles"

    link_file() {
        local src="$1" dst="$2"
        if [[ -e "$dst" && ! -L "$dst" ]]; then
            mv "$dst" "${dst}.bak.$(date +%s)"
            warn "Backed up existing $dst"
        fi
        ln -sf "$src" "$dst"
        ok "Linked $dst"
    }

    link_file "$DOTFILES/.zshrc"         "$HOME/.zshrc"
    link_file "$DOTFILES/.aliases"       "$HOME/.aliases"
    link_file "$DOTFILES/.functions"     "$HOME/.functions"
    link_file "$DOTFILES/.path"          "$HOME/.path"
    link_file "$DOTFILES/config/.gitconfig" "$HOME/.gitconfig"
    link_file "$DOTFILES/config/.treeglobal" "$HOME/.treeglobal"

    mkdir -p "$XDG_CONFIG_HOME"
    link_file "$DOTFILES/config/starship/starship.toml" "$XDG_CONFIG_HOME/starship.toml"

    mkdir -p "$XDG_CONFIG_HOME/ripgrep"
    link_file "$DOTFILES/config/ripgrep/config" "$XDG_CONFIG_HOME/ripgrep/config"
    
    ok "All dotfiles symlinked"
}

# ── 5. Default Shell ─────────────────────────────────────────
set_default_shell() {
    section "Default Shell"
    local zsh_path
    zsh_path="$(command -v zsh 2>/dev/null)" || { warn "zsh not found"; return; }

    if [[ "$SHELL" != "$zsh_path" ]]; then
        if ! grep -qxF "$zsh_path" /etc/shells; then
            echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
        fi
        chsh -s "$zsh_path" || warn "Run manually: chsh -s $zsh_path"
        ok "Default shell set to zsh"
    else
        ok "Default shell is already zsh"
    fi
}

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     dotfiles installer - WSL Edition     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    install_system_packages
    install_oh_my_zsh
    install_dev_tools
    symlink_dotfiles
    set_default_shell

    echo ""
    ok "Installation complete! Restart your terminal or run: exec zsh"
    echo ""
}

main "$@"