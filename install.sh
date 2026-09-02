#!/usr/bin/env bash
# =============================================================================
#  Dotfiles Installer — Linux (openSUSE, Ubuntu, Fedora)
#  Installs system packages, dev tools, Oh My Zsh, and symlinks dotfiles.
#
#  Usage: install.sh [--with NAME]... [--without NAME]...
#    --with NAME      force-install an opt-in component (e.g. --with claude)
#    --without NAME   skip a component (e.g. --without podman)
#    --help           list all components and their default state
#  Claude (CLI + config) is opt-in; everything else installs by default.
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

# ── Pinned tool versions (Renovate bumps these via .github/renovate.json5) ──
# Each var holds the upstream release tag; strip the leading v with ${VAR#v}
# where a download URL wants the bare version.
# renovate: datasource=github-releases depName=getsops/sops
SOPS_VERSION="v3.13.3"
# renovate: datasource=github-releases depName=evilmartians/lefthook
LEFTHOOK_VERSION="v2.1.12"
# renovate: datasource=github-releases depName=cli/cli
GH_VERSION="v2.99.0"
# renovate: datasource=github-releases depName=hashicorp/terraform
TERRAFORM_VERSION="v1.16.1"
# renovate: datasource=github-releases depName=nvm-sh/nvm
NVM_VERSION="v0.40.7"
# renovate: datasource=github-releases depName=ryanoasis/nerd-fonts
NERDFONT_VERSION="v3.5.1"

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err() { echo -e "${RED}[ERR]${NC}   $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${NC}"; }

# ── Component registry ───────────────────────────────────────
# Toggleable install steps. `on` = installed by default (skip with --without),
# `off` = opt-in (enable with --with). To add a new component: add an entry
# here, then guard its install block with `want <name>`.
declare -A COMPONENT_DEFAULT=(
  [omz]=on [nvm]=on [uv]=on [rust]=on [sops]=on [zed]=on
  [claude]=off [lefthook]=on [gh]=on [terraform]=on [aws-cli]=on
  [vscode]=on [podman]=on [alacritty]=on [chrome]=on [cedilla]=on [shell]=on
  [fonts]=on [git-config]=on [dot-filter]=on
)
declare -A COMPONENT_STATE
# Filled by run_component: ok | failed | skipped | unsupported
declare -A RESULT
MODE="install"
DRY_RUN=0

want() { [[ "${COMPONENT_STATE[$1]:-off}" == "on" ]]; }

# Does this component's artifact already exist on the machine? Mirrors the
# guards inside each installer — used by doctor and --dry-run.
component_present() {
  case "$1" in
    omz) [[ -d "$HOME/.oh-my-zsh" ]] ;;
    nvm) [[ -d "${NVM_DIR:-$HOME/.nvm}" || -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvm" ]] ;;
    uv) command -v uv &> /dev/null || [[ -x "$HOME/.local/bin/uv" ]] || [[ -x "$HOME/.cargo/bin/uv" ]] ;;
    rust) command -v rustup &> /dev/null || command -v cargo &> /dev/null || [[ -x "$HOME/.cargo/bin/cargo" ]] ;;
    sops) command -v sops &> /dev/null ;;
    zed) command -v zed &> /dev/null || [[ -x "$HOME/.local/bin/zed" ]] ;;
    claude) command -v claude &> /dev/null || [[ -x "$HOME/.local/bin/claude" ]] ;;
    lefthook) command -v lefthook &> /dev/null || [[ -x "$HOME/.local/bin/lefthook" ]] ;;
    gh) command -v gh &> /dev/null ;;
    terraform) command -v terraform &> /dev/null ;;
    aws-cli) command -v aws &> /dev/null ;;
    vscode) command -v code &> /dev/null || [[ -x /usr/local/bin/code ]] ;;
    podman) command -v podman &> /dev/null ;;
    alacritty) command -v alacritty &> /dev/null ;;
    chrome) command -v google-chrome-stable &> /dev/null ;;
    cedilla) grep -qF ccedilla "$HOME/.XCompose" 2> /dev/null ;;
    shell) [[ "$(basename "$(getent passwd "$USER" 2> /dev/null | cut -d: -f7)")" == "zsh" ]] ;;
    fonts) [[ -d "$HOME/.local/share/fonts/JetBrainsMonoNerd" ]] ;;
    git-config) [[ -n "$(git config --global --get user.email 2> /dev/null)" ]] ;;
    dot-filter) [[ -n "$(git -C "$DOTFILES" config --get filter.dot-secrets.clean 2> /dev/null)" ]] ;;
    *) return 1 ;;
  esac
}

# Some components have no build for this platform; doctor and --dry-run
# report them as skipped instead of missing. Requires ARCH/DISTRO to be set.
component_supported() {
  case "$1" in
    zed | chrome) [[ "$ARCH" == "amd64" ]] ;;
    aws-cli) [[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]] ;;
    cedilla) [[ "$DISTRO" == "opensuse" || "$DISTRO" == "fedora" ]] ;;
    *) return 0 ;;
  esac
}

# Run one component's installer, recording the outcome instead of aborting the
# whole run. NOTE: the `if` context suppresses errexit inside the installer, so
# each installer must propagate failures explicitly (`|| return 1`).
run_component() {
  local name="$1" fn="$2"
  if ! want "$name"; then
    RESULT[$name]="skipped"
    return 0
  fi
  if ! component_supported "$name"; then
    RESULT[$name]="unsupported"
    return 0
  fi
  if "$fn"; then
    RESULT[$name]="ok"
  else
    RESULT[$name]="failed"
  fi
}

usage() {
  cat << EOF
Usage: install.sh [doctor] [--with NAME]... [--without NAME]... [--dry-run]

Selects which components to install. Names may be comma-separated or the flag
repeated (e.g. --with claude --without podman,chrome). Also accepts --with=NAME.

  doctor           Check the health of an installed environment (no changes)
  --with NAME      Force-install NAME (use for opt-in components like claude)
  --without NAME   Skip NAME
  --dry-run        Show what would be installed, then exit (no sudo, no changes)
  -h, --help       Show this help

Components (default state):
EOF
  local name
  for name in $(printf '%s\n' "${!COMPONENT_DEFAULT[@]}" | sort); do
    printf "  %-12s %s\n" "$name" "${COMPONENT_DEFAULT[$name]}"
  done
}

_set_component() {
  local name="$1" state="$2"
  if [[ -z "${COMPONENT_DEFAULT[$name]+x}" ]]; then
    err "Unknown component: $name"
    err "Valid components: $(printf '%s\n' "${!COMPONENT_DEFAULT[@]}" | sort | tr '\n' ' ')"
    exit 1
  fi
  COMPONENT_STATE[$name]="$state"
}

# Apply a comma-separated list of component names to a state (on|off).
_apply_list() {
  local state="$1" list="$2" name _names
  IFS=',' read -ra _names <<< "$list"
  for name in "${_names[@]}"; do
    [[ -n "$name" ]] && _set_component "$name" "$state"
  done
}

parse_args() {
  local name
  for name in "${!COMPONENT_DEFAULT[@]}"; do
    COMPONENT_STATE[$name]="${COMPONENT_DEFAULT[$name]}"
  done

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with | --without)
        local flag="$1" state="on"
        [[ "$1" == "--without" ]] && state="off"
        shift
        [[ $# -gt 0 ]] || {
          err "$flag requires a component name"
          exit 1
        }
        _apply_list "$state" "$1"
        ;;
      --with=*) _apply_list on "${1#*=}" ;;
      --without=*) _apply_list off "${1#*=}" ;;
      doctor) MODE="doctor" ;;
      --dry-run) DRY_RUN=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

# ── Architecture detection ───────────────────────────────────
detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    armv7l | armhf) ARCH="armhf" ;;
    *) ARCH="$(uname -m)" ;;
  esac
}

# ── Distro detection ─────────────────────────────────────────
detect_distro() {
  if [[ -r /proc/device-tree/model ]] && grep -qi "raspberry pi" /proc/device-tree/model 2> /dev/null; then
    echo "raspberry"
    return
  fi
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
      opensuse-tumbleweed | opensuse*) echo "opensuse" ;;
      raspbian) echo "raspberry" ;;
      ubuntu | pop | linuxmint | debian) echo "ubuntu" ;;
      fedora | rhel | rocky | almalinux) echo "fedora" ;;
      *)
        warn "Unsupported distro: $ID — attempting Ubuntu-style install"
        echo "ubuntu"
        ;;
    esac
  else
    err "Cannot detect distro"
    exit 1
  fi
}

# ── 1. System packages ───────────────────────────────────────
install_system_packages() {
  section "System Packages"
  case "$DISTRO" in
    opensuse)
      local pkgs=(
        git curl wget unzip tar make gcc gcc-c++ gawk jq findutils
        fzf bat eza fd ripgrep git-delta htop tmux tree stow shfmt ShellCheck
        python3 python3-pip python3-pipx nodejs npm zsh
      )
      want podman && pkgs+=(podman buildah distrobox podman-compose podman-docker)
      sudo zypper refresh
      # --force-resolution: unattended runs must auto-resolve conflicts (e.g.
      # minimal/container images ship busybox-gawk, which blocks real gawk)
      sudo zypper install -y --no-recommends --force-resolution "${pkgs[@]}"
      ;;
    ubuntu | raspberry)
      local pkgs=(
        git curl wget unzip tar build-essential gawk jq findutils
        fzf bat fd-find ripgrep htop tmux tree stow shellcheck shfmt
        python3 python3-pip python3-venv pipx zsh
      )
      want podman && pkgs+=(podman podman-compose podman-docker)
      sudo apt-get update
      sudo apt-get install -y "${pkgs[@]}"

      # git-delta is in newer apt repos (Debian 12+, Ubuntu 22.04+); best-effort
      sudo apt-get install -y git-delta || warn "git-delta unavailable via apt — install via cargo or GitHub release"

      # Ubuntu aliases for modern tools
      [[ ! -L /usr/local/bin/bat ]] && [[ -x /usr/bin/batcat ]] && sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
      [[ ! -L /usr/local/bin/fd ]] && [[ -x /usr/bin/fdfind ]] && sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd

      # Install eza
      if ! command -v eza &> /dev/null; then
        sudo mkdir -p /etc/apt/keyrings
        if sudo apt-get install -y gnupg > /dev/null \
          && wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg; then
          echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
          sudo apt-get update && sudo apt-get install -y eza || {
            warn "eza install failed"
            sudo rm -f /etc/apt/sources.list.d/gierens.list
          }
        else
          warn "eza install failed: could not import GPG key"
          sudo rm -f /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        fi
      fi

      # Node.js
      if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
      fi
      ;;
    fedora)
      local pkgs=(
        git curl wget unzip tar make gcc gcc-c++ gawk jq findutils
        fzf bat eza fd-find ripgrep git-delta htop tmux tree stow shfmt ShellCheck
        python3 python3-pip pipx nodejs npm zsh
      )
      want podman && pkgs+=(podman buildah distrobox podman-compose podman-docker)
      sudo dnf install -y --setopt=install_weak_deps=False "${pkgs[@]}"
      ;;
  esac
  ok "System packages installed"
}

# ── 2. Oh My Zsh ─────────────────────────────────────────────
install_oh_my_zsh() {
  section "Oh My Zsh"
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no KEEP_ZSHRC=yes bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended || return 1
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
    local name="${plug%%:*}" repo="${plug#*:}"
    local dest="$ZSH_CUSTOM/plugins/$name"
    if [[ ! -d "$dest" ]]; then
      git clone --depth=1 "$repo" "$dest" || return 1
      ok "$name plugin installed"
    fi
  done
}

# ── 3. Dev Tools & Managers ──────────────────────────────────
install_nvm() {
  # nvm's installer honors XDG — an existing install may live in ~/.config/nvm
  if ! component_present nvm; then
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash || return 1
    ok "nvm installed"
  else
    ok "nvm already installed"
  fi

}

install_uv() {
  if ! command -v uv &> /dev/null && [ ! -f "$HOME/.local/bin/uv" ] && [ ! -f "$HOME/.cargo/bin/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh || return 1
    ok "uv installed"
  else
    ok "uv already installed"
  fi

}

install_rust() {
  if ! command -v rustup &> /dev/null \
    && ! command -v cargo &> /dev/null \
    && [ ! -f "$HOME/.cargo/bin/rustup" ] \
    && [ ! -f "$HOME/.cargo/bin/cargo" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path || return 1
    ok "rustup installed"
  else
    ok "rustup already installed"
  fi

}

install_sops() {
  if ! command -v sops &> /dev/null; then
    local sops_url="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${ARCH}"
    sudo curl -fLo /usr/local/bin/sops "$sops_url" || return 1
    sudo chmod +x /usr/local/bin/sops || return 1
    ok "sops installed"
  else
    ok "sops already installed"
  fi

}

install_zed() {
  if ! command -v zed &> /dev/null && [ ! -f "$HOME/.local/bin/zed" ]; then
    if [[ "$ARCH" != "amd64" ]]; then
      warn "Zed has no Linux ${ARCH} build — skipping"
    else
      curl -f https://zed.dev/install.sh | sh || return 1
      ok "zed installed"
    fi
  else
    ok "zed already installed"
  fi

}

install_claude_code() {
  if ! command -v claude &> /dev/null && [ ! -f "$HOME/.local/bin/claude" ]; then
    curl -fsSL https://claude.ai/install.sh | bash || return 1
    ok "claude code installed"
  else
    ok "claude code already installed"
  fi

}

# lefthook — pre-commit runner; not in distro repos
install_lefthook() {
  if ! command -v lefthook &> /dev/null && [ ! -f "$HOME/.local/bin/lefthook" ]; then
    local lefthook_arch
    case "$ARCH" in
      amd64) lefthook_arch="x86_64" ;;
      arm64) lefthook_arch="aarch64" ;;
      *) lefthook_arch="$ARCH" ;;
    esac
    mkdir -p "$HOME/.local/bin"
    curl -fsSL -o "$HOME/.local/bin/lefthook" \
      "https://github.com/evilmartians/lefthook/releases/download/${LEFTHOOK_VERSION}/lefthook_${LEFTHOOK_VERSION#v}_Linux_${lefthook_arch}" || return 1
    chmod +x "$HOME/.local/bin/lefthook" || return 1
    ok "lefthook installed"
  else
    ok "lefthook already installed"
  fi

}

# gh — GitHub CLI
install_gh() {
  if ! command -v gh &> /dev/null; then
    local gh_arch
    case "$ARCH" in
      amd64) gh_arch="amd64" ;;
      arm64) gh_arch="arm64" ;;
      armhf) gh_arch="armv6" ;;
      *) gh_arch="amd64" ;;
    esac
    local gh_tmp
    gh_tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/cli/cli/releases/download/${GH_VERSION}/gh_${GH_VERSION#v}_linux_${gh_arch}.tar.gz" \
      | tar xz -C "$gh_tmp" --strip-components=1; then
      sudo install -m 755 "$gh_tmp/bin/gh" /usr/local/bin/gh
      ok "gh ${GH_VERSION} installed"
    else
      warn "gh download failed"
      rm -rf "$gh_tmp"
      return 1
    fi
    rm -rf "$gh_tmp"
  else
    ok "gh already installed"
  fi

}

install_terraform() {
  if ! command -v terraform &> /dev/null; then
    local tf_arch
    case "$ARCH" in
      amd64) tf_arch="amd64" ;;
      arm64) tf_arch="arm64" ;;
      armhf) tf_arch="arm" ;;
      *) tf_arch="amd64" ;;
    esac
    local tf_tmp
    tf_tmp="$(mktemp -d)"
    if curl -fsSL -o "$tf_tmp/terraform.zip" \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION#v}/terraform_${TERRAFORM_VERSION#v}_linux_${tf_arch}.zip" \
      && unzip -q "$tf_tmp/terraform.zip" -d "$tf_tmp"; then
      sudo install -m 755 "$tf_tmp/terraform" /usr/local/bin/terraform
      ok "terraform ${TERRAFORM_VERSION} installed"
    else
      warn "terraform download failed"
      rm -rf "$tf_tmp"
      return 1
    fi
    rm -rf "$tf_tmp"
  else
    ok "terraform already installed"
  fi

}

# aws-cli — v2; upstream ships no 32-bit ARM build
install_awscli() {
  if ! command -v aws &> /dev/null; then
    local aws_arch=""
    case "$ARCH" in
      amd64) aws_arch="x86_64" ;;
      arm64) aws_arch="aarch64" ;;
      *) warn "AWS CLI v2 has no Linux ${ARCH} build — skipping" ;;
    esac
    if [[ -n "$aws_arch" ]]; then
      local aws_tmp
      aws_tmp="$(mktemp -d)"
      if curl -fsSL -o "$aws_tmp/awscliv2.zip" \
        "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" \
        && unzip -q "$aws_tmp/awscliv2.zip" -d "$aws_tmp"; then
        sudo "$aws_tmp/aws/install" > /dev/null
        ok "aws-cli installed"
      else
        warn "aws-cli download failed"
        rm -rf "$aws_tmp"
        return 1
      fi
      rm -rf "$aws_tmp"
    fi
  else
    ok "aws-cli already installed"
  fi

}

install_vscode() {
  if ! command -v code &> /dev/null && [ ! -f "/usr/local/bin/code" ]; then
    case "$DISTRO" in
      opensuse)
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
          | sudo tee /etc/zypp/repos.d/vscode.repo > /dev/null
        sudo zypper refresh
        sudo zypper install --no-confirm code || return 1
        ok "VSCode installed"
        ;;
      ubuntu)
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
          | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y code || return 1
        ok "VSCode installed"
        ;;
      fedora)
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
          | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
        sudo dnf check-update -y || true
        sudo dnf install -y code || return 1
        ok "VSCode installed"
        ;;
      *)
        warn "Unknown distro '$DISTRO'; skipping VSCode installation"
        ;;
    esac
  else
    ok "VSCode already installed"
  fi
}

# CLI install + config restore as one component.
install_claude() {
  install_claude_code || return 1
  install_claude_config
}

# Dispatcher — each tool runs only when its component is enabled; outcomes are
# recorded per component and reported by print_summary.
install_dev_tools() {
  section "Development Tools"
  run_component nvm install_nvm
  run_component uv install_uv
  run_component rust install_rust
  run_component sops install_sops
  run_component zed install_zed
  run_component claude install_claude
  run_component lefthook install_lefthook
  run_component gh install_gh
  run_component terraform install_terraform
  run_component aws-cli install_awscli
  run_component vscode install_vscode
  return 0
}

# ── 3b. Alacritty (distro package, fall back to source build) ──────
install_alacritty() {
  section "Alacritty"

  if command -v alacritty &> /dev/null; then
    ok "alacritty already installed ($(alacritty --version 2>&1 | head -1))"
    return
  fi

  # Try distro package first — these are built with Wayland + X11 support.
  local pkg_ok=0
  case "$DISTRO" in
    opensuse)
      sudo zypper install -y --no-recommends alacritty && pkg_ok=1 || warn "zypper could not install alacritty"
      ;;
    ubuntu | raspberry)
      sudo apt-get install -y alacritty && pkg_ok=1 || warn "apt could not install alacritty (older Ubuntu/Debian may need a PPA)"
      ;;
    fedora)
      sudo dnf install -y alacritty && pkg_ok=1 || warn "dnf could not install alacritty"
      ;;
  esac

  if [[ "$pkg_ok" == "1" ]] && command -v alacritty &> /dev/null; then
    ok "alacritty installed via distro package"
    return
  fi

  # Source build fallback — needs Rust (provided by install_dev_tools) + native deps.
  warn "Falling back to source build (Wayland + X11)"

  case "$DISTRO" in
    opensuse)
      sudo zypper install -y --no-recommends \
        cmake pkg-config freetype2-devel fontconfig-devel \
        libxcb-devel libxkbcommon-devel wayland-devel python3 || {
        err "Could not install alacritty build dependencies"
        return 1
      }
      ;;
    ubuntu | raspberry)
      sudo apt-get install -y \
        cmake pkg-config libfreetype6-dev libfontconfig1-dev \
        libxcb-xfixes0-dev libxkbcommon-dev libwayland-dev python3 || {
        err "Could not install alacritty build dependencies"
        return 1
      }
      ;;
    fedora)
      sudo dnf install -y \
        cmake pkg-config freetype-devel fontconfig-devel \
        libxcb-devel libxkbcommon-devel wayland-devel python3 || {
        err "Could not install alacritty build dependencies"
        return 1
      }
      ;;
  esac

  # Source rustup env for this shell so `cargo` is on PATH right after install_dev_tools.
  # shellcheck disable=SC1091
  [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

  if ! command -v cargo &> /dev/null; then
    err "cargo not found — rustup may have failed; cannot build alacritty from source"
    return 1
  fi

  local src_dir="$HOME/.cache/dotfiles/alacritty-src"
  mkdir -p "$(dirname "$src_dir")"
  if [[ -d "$src_dir/.git" ]]; then
    git -C "$src_dir" fetch --depth=1 origin master
    git -C "$src_dir" reset --hard origin/master
  else
    git clone --depth=1 https://github.com/alacritty/alacritty.git "$src_dir"
  fi

  (cd "$src_dir" && cargo build --release --features=wayland,x11) || {
    err "alacritty source build failed"
    return 1
  }

  install -Dm755 "$src_dir/target/release/alacritty" "$HOME/.local/bin/alacritty"
  install -Dm644 "$src_dir/extra/logo/alacritty-term.svg" \
    "$HOME/.local/share/icons/hicolor/scalable/apps/Alacritty.svg"
  install -Dm644 "$src_dir/extra/linux/Alacritty.desktop" \
    "$HOME/.local/share/applications/Alacritty.desktop"

  command -v update-desktop-database &> /dev/null \
    && update-desktop-database "$HOME/.local/share/applications" &> /dev/null || true

  ok "alacritty built from source and installed to ~/.local"
}

# ── 3c. Google Chrome ────────────────────────────────────────
install_chrome() {
  section "Google Chrome"

  if command -v google-chrome-stable &> /dev/null; then
    ok "google-chrome-stable already installed"
    return
  fi

  if [[ "$ARCH" != "amd64" ]]; then
    warn "Google Chrome has no Linux ${ARCH} build — skipping"
    return
  fi

  case "$DISTRO" in
    opensuse)
      sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
      sudo zypper --non-interactive addrepo --refresh --gpgcheck \
        https://dl.google.com/linux/chrome/rpm/stable/x86_64 google-chrome || true
      sudo zypper --gpg-auto-import-keys refresh
      sudo zypper install -y google-chrome-stable || return 1
      ;;
    ubuntu | raspberry)
      sudo install -d -m 0755 /usr/share/keyrings
      curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y google-chrome-stable || return 1
      ;;
    fedora)
      sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
      sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
      sudo dnf install -y google-chrome-stable || return 1
      ;;
    *)
      warn "Unknown distro '$DISTRO'; skipping Google Chrome installation"
      return
      ;;
  esac

  ok "google-chrome-stable installed"
}

# ── 4. Symlink Dotfiles ──────────────────────────────────────
# Move any pre-existing file/dir/foreign-symlink under $pkg into $BACKUP_DIR,
# preserving its relative path. Skips destinations that already resolve to the
# expected target in this repo, so re-runs don't churn.
backup_conflicts() {
  local pkg="$1" src rel dest expected resolved expected_resolved
  while IFS= read -r src; do
    rel="${src#"$pkg"/}"
    dest="$HOME/$rel"
    expected="$DOTFILES/stow/$pkg/$rel"

    [[ -e "$dest" || -L "$dest" ]] || continue

    # readlink -f resolves through every symlinked ancestor, so this correctly
    # skips both leaf-symlinks AND files reached via a folded parent symlink
    # (stow likes to fold ~/.config/<pkg> into one dir-level symlink).
    resolved="$(readlink -f "$dest" 2> /dev/null || true)"
    expected_resolved="$(readlink -f "$expected" 2> /dev/null || true)"
    if [[ -n "$resolved" && "$resolved" == "$expected_resolved" ]]; then
      continue
    fi

    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$dest" "$BACKUP_DIR/$rel"
    warn "Backed up $dest -> $BACKUP_DIR/$rel"
  done < <(find "$pkg" ! -type d)
}

symlink_dotfiles() {
  section "Symlinking Dotfiles with Stow"

  if ! command -v stow &> /dev/null; then
    err "stow is not installed — cannot symlink dotfiles"
    err "Install it manually: sudo zypper install stow  (or apt-get install stow / dnf install stow)"
    return 1
  fi

  cd "$DOTFILES/stow" || {
    warn "stow directory not found"
    return
  }

  # Lazily created on first conflict — re-runs that need no backup leave no trace.
  BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y-%m-%d-%H%M%S)"

  for pkg in *; do
    [[ -d "$pkg" ]] || continue

    # Remove broken symlinks that would block this package
    while IFS= read -r src; do
      dest="$HOME/${src#"$pkg"/}"
      if [[ -L "$dest" && ! -e "$dest" ]]; then
        warn "Removing broken symlink: $dest"
        rm "$dest"
      fi
    done < <(find "$pkg" ! -type d)

    # Back up anything that would conflict so stow can take ownership cleanly
    backup_conflicts "$pkg"

    # Dry-run as a safety net — after backup this should always succeed.
    if ! stow -n -R -t "$HOME" "$pkg" 2> /dev/null; then
      err "Unexpected stow conflict in $pkg after backup — inspect manually"
      continue
    fi

    stow -R -t "$HOME" "$pkg"
    ok "Stowed $pkg"
  done

  if [[ -d "$BACKUP_DIR" ]]; then
    info "Pre-existing files backed up under: $BACKUP_DIR"
  fi

  cd "$DOTFILES"
}

# ── 5. Cedilla fix (RPM-based distros, BR/PT-BR on US keyboard) ───────
fix_cedilla() {
  case "$DISTRO" in
    opensuse | fedora) ;;
    *) return ;;
  esac
  section "Cedilla Fix"
  bash "$DOTFILES/scripts/fix-cedilla.sh"
}

# ── 6. Claude Code config ────────────────────────────────────
install_claude_config() {
  section "Claude Code Config"
  if ! command -v claude &> /dev/null && [[ ! -x "$HOME/.local/bin/claude" ]]; then
    warn "claude CLI not found — skipping Claude config restore"
    return
  fi
  if [[ ! -d "$DOTFILES/claude" ]]; then
    warn "No claude/ config in repo — skipping"
    return
  fi
  # Plugin install failures (offline / not logged in) are tolerated by the
  # script, so this never aborts the installer.
  bash "$DOTFILES/scripts/claude-sync.sh" restore
  ok "Claude config restored"
}

# ── 6b. Nerd Font (JetBrainsMono, for prompt glyphs) ─────────
install_nerd_font() {
  section "Nerd Font"
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
  if [[ -d "$font_dir" ]]; then
    ok "JetBrainsMono Nerd Font already installed"
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/font.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONT_VERSION}/JetBrainsMono.zip" \
    && mkdir -p "$font_dir" \
    && unzip -q "$tmp/font.zip" -d "$font_dir"; then
    # fontconfig may be absent on headless machines; the files still land.
    if command -v fc-cache &> /dev/null; then
      fc-cache -f "$font_dir" > /dev/null || true
    fi
    ok "JetBrainsMono Nerd Font installed — select it in your terminal"
  else
    warn "Nerd Font download failed"
    rm -rf "$tmp" "$font_dir"
    return 1
  fi
  rm -rf "$tmp"
}

# ── 6c. Git identity from dotfiles.toml ──────────────────────
# No-op (with a hint) when dotfiles.toml is absent or still has placeholders;
# the installer itself never prompts.
setup_git_identity() {
  section "Git Identity"
  bash "$DOTFILES/scripts/setup-git.sh" --non-interactive
}

# ── 6d. Secret-redaction git filter ──────────────────────────
setup_secret_filter() {
  section "Secret Redaction Filter"
  bash "$DOTFILES/scripts/filter-install.sh"
}

# ── 7. Default Shell ─────────────────────────────────────────
set_default_shell() {
  section "Default Shell"
  local zsh_path
  zsh_path="$(command -v zsh 2> /dev/null)" || {
    warn "zsh not found"
    return
  }

  # Avoid the chsh password prompt when zsh is already the login shell.
  # Compare via basename + real login shell from passwd, since $SHELL may
  # disagree with `command -v zsh` on the path (e.g. /bin/zsh vs /usr/bin/zsh).
  local login_shell
  login_shell="$(getent passwd "$USER" 2> /dev/null | cut -d: -f7)"
  if [[ "$(basename "${login_shell:-$SHELL}")" == "zsh" ]]; then
    ok "Default shell is already zsh"
    return
  fi

  if ! grep -qxF "$zsh_path" /etc/shells; then
    echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
  fi
  chsh -s "$zsh_path" || warn "Run manually: chsh -s $zsh_path"
  ok "Default shell set to zsh"
}

# ── 8. Doctor / dry-run / summary ────────────────────────────
sorted_components() { printf '%s\n' "${!COMPONENT_DEFAULT[@]}" | sort; }

# Verify every enabled component is present and every stow-managed file
# resolves into this repo. Read-only; exits non-zero on any failure.
doctor() {
  section "Doctor"
  local fails=0 name

  while IFS= read -r name; do
    if ! want "$name"; then
      printf '  %-12s %b\n' "$name" "${YELLOW}skipped${NC} (disabled)"
    elif ! component_supported "$name"; then
      printf '  %-12s %b\n' "$name" "${YELLOW}skipped${NC} (no build for $DISTRO/$ARCH)"
    elif component_present "$name"; then
      printf '  %-12s %b\n' "$name" "${GREEN}ok${NC}"
    else
      printf '  %-12s %b\n' "$name" "${RED}missing${NC}"
      fails=$((fails + 1))
    fi
  done < <(sorted_components)

  section "Stow symlinks"
  if ! command -v find &> /dev/null; then
    err "find not available — cannot verify stow symlinks"
    fails=$((fails + 1))
  else
    local pkg src rel dest stow_bad=0
    cd "$DOTFILES/stow"
    for pkg in */; do
      pkg="${pkg%/}"
      while IFS= read -r src; do
        rel="${src#"$pkg"/}"
        dest="$HOME/$rel"
        if [[ ! -e "$dest" ]]; then
          err "not stowed: ~/$rel"
          stow_bad=$((stow_bad + 1))
        elif [[ "$(readlink -f "$dest" 2> /dev/null)" != "$(readlink -f "$src")" ]]; then
          err "wrong target: ~/$rel -> $(readlink -f "$dest" 2> /dev/null || echo '?')"
          stow_bad=$((stow_bad + 1))
        fi
      done < <(find "$pkg" ! -type d)
    done
    cd "$DOTFILES"
    if [[ "$stow_bad" == 0 ]]; then
      ok "All stow-managed files resolve into the repo"
    else
      fails=$((fails + stow_bad))
    fi
  fi

  section "Config"
  if [[ -f "$DOTFILES/dotfiles.toml" || -f "$DOTFILES/dotfiles.sops.toml" ]]; then
    ok "dotfiles.toml present"
  else
    warn "no dotfiles.toml — cp dotfiles.toml.example dotfiles.toml to enable git identity + secrets"
  fi

  echo ""
  if [[ "$fails" == 0 ]]; then
    ok "Doctor: healthy"
  else
    err "Doctor: $fails problem(s) found"
    return 1
  fi
}

# Print what an install run would do, without touching the system.
dry_run_report() {
  section "Dry Run"
  local name
  while IFS= read -r name; do
    if ! want "$name"; then
      printf '  %-12s %b\n' "$name" "${YELLOW}disabled${NC}"
    elif ! component_supported "$name"; then
      printf '  %-12s %b\n' "$name" "${YELLOW}skipped${NC} (no build for $DISTRO/$ARCH)"
    elif component_present "$name"; then
      printf '  %-12s %b\n' "$name" "${GREEN}already present${NC}"
    else
      printf '  %-12s %b\n' "$name" "${CYAN}would install${NC}"
    fi
  done < <(sorted_components)
  echo ""
  info "System packages and stow symlinks are always processed on a real run."
}

# End-of-run outcome table + remaining manual steps. Exits non-zero if any
# component failed so CI and scripts can rely on the exit code.
print_summary() {
  section "Summary"
  local name state failed=0
  while IFS= read -r name; do
    state="${RESULT[$name]:-}"
    case "$state" in
      ok) printf '  %-12s %b\n' "$name" "${GREEN}ok${NC}" ;;
      failed)
        printf '  %-12s %b\n' "$name" "${RED}failed${NC}"
        failed=$((failed + 1))
        ;;
      skipped) printf '  %-12s %b\n' "$name" "${YELLOW}skipped${NC}" ;;
      unsupported) printf '  %-12s %b\n' "$name" "${YELLOW}skipped${NC} (no build for $DISTRO/$ARCH)" ;;
      *) printf '  %-12s %b\n' "$name" "-" ;;
    esac
  done < <(sorted_components)

  echo ""
  info "Next steps:"
  if [[ ! -f "$DOTFILES/dotfiles.toml" && ! -f "$DOTFILES/dotfiles.sops.toml" ]]; then
    info "  - cp dotfiles.toml.example dotfiles.toml  # git identity + secrets"
  fi
  if [[ -z "$(git config --get user.email 2> /dev/null)" ]]; then
    info "  - ./scripts/setup-git.sh                  # git identity + GPG signing"
  fi
  info "  - ./scripts/setup-ssh-github.sh           # SSH key + upload to GitHub"
  info "  - ./scripts/setup-gpg-github.sh           # GPG key + upload to GitHub"
  info "  - bash install.sh doctor                  # verify this environment"

  if [[ "$failed" -gt 0 ]]; then
    echo ""
    err "$failed component(s) failed — scroll up for details"
    return 1
  fi
}

main() {
  parse_args "$@"

  detect_arch
  DISTRO="$(detect_distro)"
  info "Detected distro: $DISTRO ($ARCH)"

  # Tools installed below land in ~/.local/bin, ~/.cargo/bin and
  # /usr/local/bin; a fresh machine's (or sudo secure_path's) PATH may not
  # include them yet, so later probes in this same run — and re-run
  # idempotency checks — would miss them without this.
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

  if [[ "$MODE" == "doctor" ]]; then
    doctor
    exit
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    dry_run_report
    exit 0
  fi

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║     dotfiles installer - Linux Native    ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
  echo ""

  install_system_packages
  # Stow before Oh My Zsh: OMZ's installer writes a template ~/.zshrc when none
  # exists, which makes stow abort the entire zsh package on conflict. Stowing
  # first means OMZ (run with KEEP_ZSHRC=yes) sees the symlink and leaves it.
  symlink_dotfiles
  run_component omz install_oh_my_zsh
  install_dev_tools
  run_component alacritty install_alacritty
  run_component chrome install_chrome
  run_component fonts install_nerd_font
  run_component git-config setup_git_identity
  run_component dot-filter setup_secret_filter
  run_component cedilla fix_cedilla
  run_component shell set_default_shell

  echo ""
  ok "Installation complete! Restart your terminal or run: exec zsh"
  print_summary
}

main "$@"
