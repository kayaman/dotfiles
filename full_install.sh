#!/usr/bin/env bash

set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  dotfiles installer — openSUSE Tumbleweed & Ubuntu
# ─────────────────────────────────────────────────────────────

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
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
            # Uses --no-recommends intentionally to minimize installed packages,
            # reduce disk usage, and limit unnecessary dependencies.
            sudo zypper install -y --no-recommends "$@"
            ;;
        ubuntu)
            sudo apt-get install -y "$@"
            ;;
    esac
}

add_opensuse_zsh_repos() {
    local version_repo
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            opensuse-tumbleweed) version_repo="openSUSE_Tumbleweed" ;;
            opensuse)
                version_repo="openSUSE_Leap_${VERSION_ID:-15.6}"
                ;;
            *)
                version_repo="openSUSE_Tumbleweed"
                warn "Unknown openSUSE variant, using Tumbleweed repo"
                ;;
        esac
    else
        version_repo="openSUSE_Tumbleweed"
    fi

    local base="https://download.opensuse.org/repositories"
    for repo in shells:zsh-users:zsh-syntax-highlighting shells:zsh-users:zsh-autosuggestions; do
        local alias="${repo//:/-}"
        local repo_url="$base/$repo/$version_repo/${repo}.repo"
        if ! zypper lr "$alias" &>/dev/null 2>&1; then
            info "Adding repo: $repo"
            sudo zypper addrepo -f -n "$alias" "$repo_url" || true
        fi
    done
}

install_system_packages() {
    info "Installing system packages..."

    case "$DISTRO" in
        opensuse)
            sudo zypper refresh
            pkg_install \
                git curl wget unzip tar \
                make gcc gawk \
                fzf bat eza fd ripgrep git-delta \
                zsh python3 python3-pip nodejs npm jq htop tmux
            add_opensuse_zsh_repos
            sudo zypper refresh 2>/dev/null || true
            pkg_install zsh-syntax-highlighting zsh-autosuggestions 2>/dev/null || {
                warn "zsh-syntax-highlighting / zsh-autosuggestions not installed — add shells:zsh-users repos manually or install from git"
            }
            ;;
        ubuntu)
            sudo apt-get update
            pkg_install \
                git curl wget unzip tar \
                build-essential gawk \
                fzf bat fd-find ripgrep \
                zsh zsh-syntax-highlighting zsh-autosuggestions \
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
                # NOTE: This downloads and executes a remote setup script.
                # Review https://deb.nodesource.com/setup_lts.x before running
                # on sensitive systems, or install nodejs via apt from Ubuntu repos.
                local nodesource_setup
                nodesource_setup="$(mktemp /tmp/nodesource-setup-XXXX.sh)"
                curl -fsSL -o "$nodesource_setup" https://deb.nodesource.com/setup_lts.x
                sudo -E bash "$nodesource_setup"
                rm -f "$nodesource_setup"
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
    local deb_file="git-delta_${delta_ver}_${arch}.deb"
    local deb_url="https://github.com/dandavison/delta/releases/download/${delta_ver}/${deb_file}"
    local sha_url="https://github.com/dandavison/delta/releases/download/${delta_ver}/git-delta_${delta_ver}_sha256sums"
    local tmp_deb tmp_sha
    tmp_deb="$(mktemp /tmp/delta-XXXX.deb)"
    tmp_sha="$(mktemp /tmp/delta-sha256-XXXX.txt)"
    if curl -fsSL -o "$tmp_deb" "$deb_url" && curl -fsSL -o "$tmp_sha" "$sha_url"; then
        local expected actual
        expected="$(grep "$deb_file" "$tmp_sha" | awk '{print $1}')"
        actual="$(sha256sum "$tmp_deb" | awk '{print $1}')"
        if [[ "$expected" == "$actual" ]]; then
            sudo dpkg -i "$tmp_deb" || {
                warn "delta install failed — git diffs will use default pager"
            }
        else
            warn "delta checksum mismatch — skipping install (expected: $expected, got: $actual)"
        fi
    else
        warn "delta download failed — git diffs will use default pager"
    fi
    rm -f "$tmp_deb" "$tmp_sha"
}

install_package_managers() {
    # NOTE: The following installers are downloaded and executed locally.
    # Review each script before running on sensitive systems.

    # rvm — https://rvm.io/rvm/install
    gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
    local rvm_installer
    rvm_installer="$(mktemp /tmp/rvm-install-XXXX.sh)"
    curl -sSL -o "$rvm_installer" https://get.rvm.io
    bash "$rvm_installer"
    rm -f "$rvm_installer"

    # nvm — https://github.com/nvm-sh/nvm
    local nvm_installer
    nvm_installer="$(mktemp /tmp/nvm-install-XXXX.sh)"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh > "$nvm_installer"
    bash "$nvm_installer"
    rm -f "$nvm_installer"

    # uv — https://docs.astral.sh/uv/getting-started/installation/
    local uv_installer
    uv_installer="$(mktemp /tmp/uv-install-XXXX.sh)"
    curl -LsSf -o "$uv_installer" https://astral.sh/uv/install.sh
    sh "$uv_installer"
    rm -f "$uv_installer"
}


# ── Starship prompt ──────────────────────────────────────────
install_starship() {
    if command -v starship &>/dev/null; then
        ok "starship already installed"
        return
    fi

    info "Installing starship prompt..."
    # NOTE: Downloads and executes a remote installer — review https://starship.rs/install.sh
    # before running on sensitive systems, or install via your distro's package manager.
    local starship_installer
    starship_installer="$(mktemp /tmp/starship-install-XXXX.sh)"
    curl -fsSL -o "$starship_installer" https://starship.rs/install.sh
    sh "$starship_installer" -y
    rm -f "$starship_installer"
    ok "starship installed"
}

# ── Symlink dotfiles ─────────────────────────────────────────
link_file() {
    local src="$1" dst="$2"
    if [[ -e "$dst" ]] && [[ ! -L "$dst" ]]; then
        local backup="${dst}.bak.$(date +%s)"
        warn "Backing up existing $dst → $backup"
        mv "$dst" "$backup"
    fi
    ln -sf "$src" "$dst"
    ok "Linked $dst → $src"
}

set_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh 2>/dev/null)"
    if [[ -z "$zsh_path" ]]; then
        warn "zsh not found — cannot set default shell"
        return
    fi
    if [[ "$SHELL" == "$zsh_path" ]]; then
        ok "zsh is already the default shell"
        return
    fi
    echo ""
    read -r -p "Set zsh as default login shell? [y/N] " response
    if [[ "${response,,}" =~ ^(y|yes)$ ]]; then
        if chsh -s "$zsh_path" 2>/dev/null; then
            ok "Default shell set to zsh (log out and back in to apply)"
        else
            warn "chsh failed. Ensure $zsh_path is in /etc/shells. Example:"
            info "  sudo sh -c 'echo $zsh_path >> /etc/shells'"
            info "Then run: chsh -s $zsh_path"
        fi
    else
        info "Skipped. Run 'chsh -s \$(which zsh)' later to set zsh as default."
    fi
    echo ""
}

symlink_dotfiles() {
    info "Symlinking dotfiles..."

    # Shared configs
    link_file "$DOTFILES_DIR/common/aliases.sh" "$HOME/.aliases"
    link_file "$DOTFILES_DIR/.functions"         "$HOME/.functions"

    # Zsh config
    link_file "$DOTFILES_DIR/.zshrc"             "$HOME/.zshrc"

    # Readline
    link_file "$DOTFILES_DIR/bash/.inputrc"      "$HOME/.inputrc"

    # Starship, ripgrep
    mkdir -p "$XDG_CONFIG_HOME"
    link_file "$DOTFILES_DIR/config/starship/starship.toml" "$XDG_CONFIG_HOME/starship.toml"
    mkdir -p "$XDG_CONFIG_HOME/ripgrep"
    link_file "$DOTFILES_DIR/config/ripgrep/config" "$XDG_CONFIG_HOME/ripgrep/config"

    # Git
    link_file "$DOTFILES_DIR/config/.gitconfig" "$HOME/.gitconfig"

    ok "All dotfiles symlinked"
}

# ── Main ─────────────────────────────────────────────────────
main() {
    local install_pms=false
    [[ "${1:-}" == "--package-managers" ]] && install_pms=true

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        dotfiles installer                ║${NC}"
    echo -e "${CYAN}║   zsh + starship + fzf                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    install_system_packages
    install_starship
    $install_pms && install_package_managers
    symlink_dotfiles
    set_default_shell

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Installation complete!          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    info "Open a new terminal or run: exec zsh"
    echo ""
}

main "$@"
