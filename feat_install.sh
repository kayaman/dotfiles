#!/usr/bin/env bash
# =============================================================================
#  Dotfiles Installer — Linux (openSUSE & Ubuntu)
#  Installs system packages, dev tools, Oh My Zsh, Starship, and symlinks dotfiles.
# =============================================================================

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# ── Distro detection ─────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            opensuse-tumbleweed|opensuse) echo "opensuse" ;;
            ubuntu|pop|linuxmint|debian)  echo "ubuntu"   ;;
            *)
                warn "Unsupported distro: $ID — attempting Ubuntu-style install"
                echo "ubuntu"
                ;;
        esac
    else
        err "Cannot detect distro"; exit 1
    fi
}

DISTRO="$(detect_distro)"
info "Detected distro: $DISTRO"

# ── 1. System packages ───────────────────────────────────────
install_system_packages() {
    section "System Packages"
    case "$DISTRO" in
        opensuse)
            sudo zypper refresh
            sudo zypper install -y --no-recommends \
                git curl wget unzip tar make gcc gcc-c++ gawk jq \
                fzf bat eza fd ripgrep git-delta htop tmux tree stow \
                python3 python3-pip python3-pipx nodejs npm \
                zsh podman buildah distrobox docker docker-compose
            ;;
        ubuntu)
            sudo apt-get update
            sudo apt-get install -y \
                git curl wget unzip tar build-essential gawk jq \
                fzf bat fd-find ripgrep htop tmux tree stow \
                python3 python3-pip python3-venv pipx \
                zsh podman docker.io docker-compose

            # Ubuntu aliases for modern tools
            [[ ! -L /usr/local/bin/bat ]] && [[ -x /usr/bin/batcat ]] && sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
            [[ ! -L /usr/local/bin/fd ]] && [[ -x /usr/bin/fdfind ]] && sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd

            # Install eza
            if ! command -v eza &>/dev/null; then
                sudo mkdir -p /etc/apt/keyrings
                wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null || true
                echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
                sudo apt-get update && sudo apt-get install -y eza || warn "eza install failed"
            fi

            # Node.js
            if ! command -v node &>/dev/null; then
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                sudo apt-get install -y nodejs
            fi
            ;;
    esac
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

    # antigravity-usage
    if ! command -v antigravity-usage &>/dev/null; then
        sudo npm install -g antigravity-usage
        ok "antigravity-usage installed"
    else
        ok "antigravity-usage already installed"
    fi

    # sops
    if ! command -v sops &>/dev/null; then
        local sops_version="v3.8.1"
        local sops_url="https://github.com/getsops/sops/releases/download/${sops_version}/sops-${sops_version}.linux-amd64"
        sudo curl -Lo /usr/local/bin/sops "$sops_url"
        sudo chmod +x /usr/local/bin/sops
        ok "sops installed"
    else
        ok "sops already installed"
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
    section "Symlinking Dotfiles with Stow"

    cd "$DOTFILES/stow" || { warn "stow directory not found"; return; }
    
    for pkg in *; do
        if [[ -d "$pkg" ]]; then
            stow -R -t "$HOME" "$pkg"
            ok "Stowed $pkg"
        fi
    done
    
    cd "$DOTFILES"
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
    echo -e "${CYAN}║     dotfiles installer - Linux Native    ║${NC}"
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