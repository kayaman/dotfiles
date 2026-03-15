#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  Bootstrap — openSUSE Tumbleweed
#  zsh + oh-my-zsh + plugins + starship + dotfiles
#  Optional: restore GPG keys and env vars from USB drive
#
#  Usage:
#    bash bootstrap.sh [--usb /run/media/$USER/DRIVE] [--package-managers]
# ─────────────────────────────────────────────────────────────

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

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
fatal() { err "$*"; exit 1; }

# ── Argument parsing ──────────────────────────────────────────
USB_PATH=""
INSTALL_PMS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --usb)
            USB_PATH="${2:-}"
            [[ -z "$USB_PATH" ]] && fatal "--usb requires a path argument"
            shift 2
            ;;
        --package-managers)
            INSTALL_PMS=true
            shift
            ;;
        *)
            err "Unknown argument: $1"
            echo "Usage: $0 [--usb /path/to/usb] [--package-managers]"
            exit 1
            ;;
    esac
done

# ── Sanity checks ─────────────────────────────────────────────
[[ -f /etc/os-release ]] || fatal "Cannot detect distro — /etc/os-release not found"
. /etc/os-release
[[ "$ID" == "opensuse-tumbleweed" ]] || \
    warn "Expected opensuse-tumbleweed, got '$ID' — proceeding anyway"

# ── System packages ───────────────────────────────────────────
install_system_packages() {
    info "Refreshing zypper repos..."
    sudo zypper refresh

    info "Installing system packages..."
    sudo zypper install -y --no-recommends \
        git curl wget unzip tar \
        make gcc gawk \
        fzf bat eza fd ripgrep git-delta \
        zsh \
        python3 python3-pip \
        nodejs npm \
        jq htop tmux \
        gnupg2

    ok "System packages installed"
}

# ── Oh My Zsh ─────────────────────────────────────────────────
install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ok "oh-my-zsh already installed"
        return
    fi

    info "Installing oh-my-zsh..."
    local installer
    installer="$(mktemp /tmp/ohmyzsh-install-XXXX.sh)"
    curl -fsSL -o "$installer" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
    # RUNZSH=no skips launching zsh so the script can continue
    RUNZSH=no CHSH=no bash "$installer" --unattended
    rm -f "$installer"
    ok "oh-my-zsh installed at $HOME/.oh-my-zsh"
}

# ── Oh My Zsh plugins ─────────────────────────────────────────
install_zsh_plugin() {
    local name="$1" repo="$2"
    local dir="$HOME/.oh-my-zsh/custom/plugins/$name"
    if [[ -d "$dir" ]]; then
        info "Plugin '$name' already installed — pulling latest..."
        git -C "$dir" pull --ff-only 2>/dev/null || true
        return
    fi
    info "Installing plugin: $name"
    git clone --depth 1 "$repo" "$dir"
    ok "Plugin '$name' installed"
}

install_zsh_plugins() {
    info "Installing oh-my-zsh plugins..."
    install_zsh_plugin zsh-autosuggestions    https://github.com/zsh-users/zsh-autosuggestions
    install_zsh_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting
    install_zsh_plugin zsh-completions         https://github.com/zsh-users/zsh-completions
    ok "All plugins installed"
}

# ── Starship prompt ───────────────────────────────────────────
install_starship() {
    if command -v starship &>/dev/null; then
        ok "starship already installed"
        return
    fi

    info "Installing starship..."
    local installer
    installer="$(mktemp /tmp/starship-install-XXXX.sh)"
    curl -fsSL -o "$installer" https://starship.rs/install.sh
    sh "$installer" -y
    rm -f "$installer"
    ok "starship installed"
}

# ── Optional package managers ─────────────────────────────────
install_package_managers() {
    info "Installing rvm..."
    gpg --keyserver keyserver.ubuntu.com \
        --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
    local rvm_installer
    rvm_installer="$(mktemp /tmp/rvm-install-XXXX.sh)"
    curl -sSL -o "$rvm_installer" https://get.rvm.io
    bash "$rvm_installer"
    rm -f "$rvm_installer"

    info "Installing nvm..."
    local nvm_installer
    nvm_installer="$(mktemp /tmp/nvm-install-XXXX.sh)"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh > "$nvm_installer"
    bash "$nvm_installer"
    rm -f "$nvm_installer"

    info "Installing uv (Python)..."
    local uv_installer
    uv_installer="$(mktemp /tmp/uv-install-XXXX.sh)"
    curl -LsSf -o "$uv_installer" https://astral.sh/uv/install.sh
    sh "$uv_installer"
    rm -f "$uv_installer"

    ok "Package managers installed"
}

# ── Symlink dotfiles ──────────────────────────────────────────
link_file() {
    local src="$1" dst="$2"
    if [[ -e "$dst" ]] && [[ ! -L "$dst" ]]; then
        local backup="${dst}.bak.$(date +%s)"
        warn "Backing up $dst → $backup"
        mv "$dst" "$backup"
    fi
    ln -sf "$src" "$dst"
    ok "Linked $dst"
}

symlink_dotfiles() {
    info "Symlinking dotfiles..."

    link_file "$DOTFILES_DIR/.zshrc"                           "$HOME/.zshrc"
    link_file "$DOTFILES_DIR/common/aliases.sh"                "$HOME/.aliases"
    link_file "$DOTFILES_DIR/.functions"                       "$HOME/.functions"
    link_file "$DOTFILES_DIR/bash/.inputrc"                    "$HOME/.inputrc"

    mkdir -p "$XDG_CONFIG_HOME"
    link_file "$DOTFILES_DIR/config/starship/starship.toml"    "$XDG_CONFIG_HOME/starship.toml"
    mkdir -p "$XDG_CONFIG_HOME/ripgrep"
    link_file "$DOTFILES_DIR/config/ripgrep/config"            "$XDG_CONFIG_HOME/ripgrep/config"

    link_file "$DOTFILES_DIR/config/.gitconfig"                "$HOME/.gitconfig"

    ok "All dotfiles symlinked"
}

# ── Default shell ─────────────────────────────────────────────
set_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh 2>/dev/null)" || { warn "zsh not found"; return; }

    if [[ "$SHELL" == "$zsh_path" ]]; then
        ok "zsh is already the default shell"
        return
    fi

    # Ensure zsh is in /etc/shells
    if ! grep -qxF "$zsh_path" /etc/shells; then
        info "Adding $zsh_path to /etc/shells"
        echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi

    if chsh -s "$zsh_path"; then
        ok "Default shell set to zsh (re-login to apply)"
    else
        warn "chsh failed — run manually: chsh -s $zsh_path"
    fi
}

# ── USB restore ───────────────────────────────────────────────
detect_usb_drive() {
    # Returns first candidate USB mount under /run/media or /media
    local candidates=()

    while IFS= read -r -d '' mount; do
        candidates+=("$mount")
    done < <(find /run/media /media -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null)

    if [[ ${#candidates[@]} -eq 0 ]]; then
        return 1
    fi

    if [[ ${#candidates[@]} -eq 1 ]]; then
        echo "${candidates[0]}"
        return 0
    fi

    # Multiple drives — ask user
    echo "" >&2
    warn "Multiple mounted drives found. Select one:" >&2
    local i=1
    for c in "${candidates[@]}"; do
        echo "  $i) $c" >&2
        ((i++))
    done
    printf "${BOLD}Enter number [1-${#candidates[@]}]: ${NC}" >&2
    read -r choice
    local idx=$(( choice - 1 ))
    echo "${candidates[$idx]}"
}

restore_gpg_keys() {
    local usb="$1"

    info "Scanning $usb for GPG key files..."
    local gpg_files=()
    while IFS= read -r -d '' f; do
        gpg_files+=("$f")
    done < <(find "$usb" -maxdepth 3 \( -name "*.asc" -o -name "*.gpg" -o -name "*.key" \) -print0 2>/dev/null)

    if [[ ${#gpg_files[@]} -eq 0 ]]; then
        warn "No GPG key files found on USB"
        return
    fi

    local gpg_bin
    gpg_bin="$(command -v gpg2 2>/dev/null || command -v gpg 2>/dev/null)" || \
        fatal "gpg not found"

    for key_file in "${gpg_files[@]}"; do
        info "Importing: $key_file"
        "$gpg_bin" --import "$key_file" && ok "Imported $key_file" || \
            warn "Failed to import $key_file — skipping"
    done

    # Set ultimate trust on any newly imported secret keys
    local fpr
    while IFS= read -r fpr; do
        echo "$fpr:6:" | "$gpg_bin" --import-ownertrust 2>/dev/null || true
    done < <("$gpg_bin" --list-secret-keys --with-colons 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10 }')

    ok "GPG restore complete"
}

restore_env_vars() {
    local usb="$1"

    info "Scanning $usb for env files..."
    local env_files=()
    while IFS= read -r -d '' f; do
        env_files+=("$f")
    done < <(find "$usb" -maxdepth 3 \( -name ".env" -o -name ".env.sh" -o -name "env.sh" \) -print0 2>/dev/null)

    if [[ ${#env_files[@]} -eq 0 ]]; then
        warn "No env files found on USB"
        return
    fi

    for env_file in "${env_files[@]}"; do
        local base_name
        base_name="$(basename "$env_file")"
        local dest="$HOME/$base_name"

        if [[ -f "$dest" ]]; then
            local backup="${dest}.bak.$(date +%s)"
            warn "Backing up existing $dest → $backup"
            cp "$dest" "$backup"
        fi

        cp "$env_file" "$dest"
        chmod 600 "$dest"
        ok "Restored $base_name to $dest"
    done
}

restore_from_usb() {
    local usb="${1:-}"

    if [[ -z "$usb" ]]; then
        info "Auto-detecting USB drive..."
        usb="$(detect_usb_drive)" || {
            warn "No USB drive found — skipping restore"
            return
        }
    fi

    [[ -d "$usb" ]] || fatal "USB path not found: $usb"
    info "Restoring from USB: $usb"

    restore_gpg_keys "$usb"
    restore_env_vars "$usb"
}

# ── Main ──────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   openSUSE Tumbleweed bootstrap          ║${NC}"
    echo -e "${CYAN}║   zsh + oh-my-zsh + starship             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    install_system_packages
    install_oh_my_zsh
    install_zsh_plugins
    install_starship

    $INSTALL_PMS && install_package_managers

    symlink_dotfiles
    set_default_shell

    if [[ -n "$USB_PATH" ]]; then
        restore_from_usb "$USB_PATH"
    else
        echo ""
        printf "${BOLD}Restore GPG keys and env vars from USB? [y/N] ${NC}"
        read -r response
        if [[ "${response,,}" =~ ^(y|yes)$ ]]; then
            restore_from_usb ""
        else
            info "Skipping USB restore. Run later with: $0 --usb /path/to/usb"
        fi
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Bootstrap complete!                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    info "Log out and back in to start using zsh"
    info "Or run: exec zsh"
    echo ""
}

main "$@"
