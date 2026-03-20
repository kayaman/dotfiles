#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  dotfiles installer — openSUSE Tumbleweed & Ubuntu
# ─────────────────────────────────────────────────────────────

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${XDG_CONFIG_HOME:="$HOME/.config"}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ── Distro detection ─────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            opensuse-tumbleweed|opensuse) echo "opensuse" ;;
            ubuntu|pop|linuxmint)         echo "ubuntu"   ;;
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

# ── Package installation ─────────────────────────────────────
pkg_install() {
    case "$DISTRO" in
        opensuse)
            sudo zypper install -y --no-recommends "$@"
            ;;
        ubuntu)
            sudo apt-get install -y "$@"
            ;;
    esac
}

install_system_packages() {
    info "Installing system packages..."

    case "$DISTRO" in
        opensuse)
            sudo zypper refresh
            pkg_install \
                bash bash-completion \
                zsh \
                git curl wget unzip tar \
                make gcc gawk \
                fzf bat eza fd ripgrep git-delta \
                python3 python3-pip \
                nodejs npm \
                jq htop tmux tree go
            ;;
        ubuntu)
            sudo apt-get update
            pkg_install \
                bash bash-completion git curl wget unzip tar \
                build-essential gawk \
                fzf bat fd-find ripgrep \
                python3 python3-pip python3-venv \
                jq htop tmux

            # Ubuntu renames some binaries
            [[ ! -L /usr/local/bin/bat ]] && [[ -x /usr/bin/batcat ]] && \
                sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
            [[ ! -L /usr/local/bin/fd ]] && [[ -x /usr/bin/fdfind ]] && \
                sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd

            # eza — not in default repos on older Ubuntu
            if ! command -v eza &>/dev/null; then
                info "Installing eza via cargo or binary..."
                install_eza_ubuntu
            fi

            # delta — not in default repos
            if ! command -v delta &>/dev/null; then
                info "Installing git-delta from GitHub releases..."
                install_delta_github
            fi

            # Node.js — use NodeSource if not present
            if ! command -v node &>/dev/null; then
                info "Installing Node.js via NodeSource..."
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                sudo apt-get install -y nodejs
            fi
            ;;
    esac
    ok "System packages installed"
}

install_eza_ubuntu() {
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null || true
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
    sudo apt-get update && sudo apt-get install -y eza || {
        warn "eza repo install failed — falling back to alias for ls"
    }
}

install_delta_github() {
    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    local delta_ver
    delta_ver="$(curl -fsSL https://api.github.com/repos/dandavison/delta/releases/latest \
        | jq -r '.tag_name')"
    local deb_url="https://github.com/dandavison/delta/releases/download/${delta_ver}/git-delta_${delta_ver}_${arch}.deb"
    local tmp
    tmp="$(mktemp /tmp/delta-XXXX.deb)"
    curl -fsSL -o "$tmp" "$deb_url" && sudo dpkg -i "$tmp" && rm -f "$tmp" || {
        warn "delta install failed — git diffs will use default pager"
    }
}

install_package_managers() {
    # rvm
    gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
    curl -sSL https://get.rvm.io | bash

    # nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

    # uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
}


# ── Starship prompt ──────────────────────────────────────────
install_starship() {
    if command -v starship &>/dev/null; then
        ok "starship already installed"
        return
    fi

    info "Installing starship prompt..."
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
    ok "starship installed"
}

# ── Symlink dotfiles ─────────────────────────────────────────
link_file() {
    local src="$1" dst="$2"
    if [[ -e "$dst" ]] && [[ ! -L "$dst" ]]; then

        warn "File $dst already exists and is not a symlink"
        warn "Skipping $dst"
        # TODO: if --overwrite
        # local backup="${dst}.bak.$(date +%s)"
        # warn "Backing up existing $dst → $backup"
        # mv "$dst" "$backup"
    elif [[ -L "$dst" ]]; then
        # Destination is a symlink: check its current target.
        local current_target
        current_target="$(readlink "$dst" || true)"
        if [[ "$current_target" == "$src" ]]; then
            ok "Symlink $dst already points to $src"
        else
            warn "Symlink $dst points to $current_target (expected $src), updating..."
            ln -sfn "$src" "$dst"
            ok "Relinked $dst → $src"
        fi
    else
        ln -sf "$src" "$dst"
        ok "Linked $dst → $src"
    fi
}

symlink_dotfiles() {
    info "Symlinking dotfiles..."

    link_file "$DOTFILES/.profile"         "$HOME/.profile"
    link_file "$DOTFILES/.zshrc"         "$HOME/.zshrc"
    link_file "$DOTFILES/.aliases"    "$HOME/.aliases"
    link_file "$DOTFILES/.functions"  "$HOME/.functions"
    link_file "$DOTFILES/config/.inputrc"   "$HOME/.inputrc"
    # link_file "$DOTFILES/.gitconfig"         "$HOME/.gitconfig"

    # Starship
    mkdir -p "$XDG_CONFIG_HOME"
    link_file "$DOTFILES/config/starship/starship.toml" "$XDG_CONFIG_HOME/starship.toml"

    # ripgrep
    mkdir -p "$XDG_CONFIG_HOME/ripgrep"
    link_file "$DOTFILES/config/ripgrep/config" "$XDG_CONFIG_HOME/ripgrep/config"

    link_file "$DOTFILES/config/.gitconfig" "$HOME/.gitconfig"
    link_file "$DOTFILES/config/.treeglobal" "$HOME/.treeglobal"

    ok "All dotfiles symlinked"
}

# ── Main ─────────────────────────────────────────────────────
main() {
    local install_pms=false
    [[ "${1:-}" == "--package-managers" ]] && install_pms=true

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        dotfiles installer                ║${NC}"
    echo -e "${CYAN}║   zsh + ohmyzsh + starship                ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    install_system_packages
    install_starship
    $install_pms && install_package_managers
    symlink_dotfiles

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Installation complete!          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    info "Open a new terminal or run: exec zsh"
    echo ""
}

main "$@"
