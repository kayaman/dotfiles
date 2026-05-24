#!/usr/bin/env bash
# =============================================================================
#  Dotfiles Bootstrap — clone & install
#  Usage: bash <(curl -fsSL https://dot.ai-assisted.dev)
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/kayaman/dotfiles.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Projects/dotfiles}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
err() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ── Require git ──────────────────────────────────────────────
if ! command -v git &> /dev/null; then
  err "git is required but not installed."
  err "Install it first: sudo apt-get install git  (or: sudo zypper install git / sudo dnf install git)"
  exit 1
fi

# ── Clone or update ──────────────────────────────────────────
if [[ -d "$DOTFILES_DIR/.git" ]]; then
  info "Dotfiles already cloned — pulling latest changes..."
  git -C "$DOTFILES_DIR" pull --ff-only
  ok "Repository updated"
else
  info "Cloning dotfiles into $DOTFILES_DIR ..."
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  git clone "$REPO_URL" "$DOTFILES_DIR"
  ok "Repository cloned"
fi

# ── Run the installer ────────────────────────────────────────
# Forward any args (e.g. --with claude, --without podman) to the installer.
info "Running installer"
bash "$DOTFILES_DIR/install.sh" "$@"
