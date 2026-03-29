#!/usr/bin/env bash
# Fix cedilla (ç) on openSUSE with US keyboard layout.
#
# When typing ' + c, the default US International compose mapping produces ć
# (c-acute). This script ensures ç (c-cedilla) is produced instead via:
#
#   ~/.XCompose          — overrides dead_acute+c for X11/XIM applications
#   environment.d/       — sets GTK_IM_MODULE=cedilla for GTK/Qt GUI apps
#                          (read by systemd for both X11 and Wayland sessions)
#
# The stow packages 'xcompose' and 'cedilla' in this repo already contain
# those files.  Run this script directly only if you need a standalone fix
# without the full dotfiles install.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }

# --- .XCompose ---------------------------------------------------------------
XCOMPOSE="$HOME/.XCompose"
XCOMPOSE_BLOCK='# Fix dead_acute + c/C → ç/Ç (Brazilian Portuguese on US keyboard)
<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla'

if [[ -L "$XCOMPOSE" ]]; then
    ok ".XCompose is a symlink (managed by stow)"
elif grep -qF 'ccedilla' "$XCOMPOSE" 2>/dev/null; then
    ok ".XCompose already contains cedilla overrides"
else
    if [[ ! -f "$XCOMPOSE" ]]; then
        printf 'include "%%L"\n\n%s\n' "$XCOMPOSE_BLOCK" > "$XCOMPOSE"
    else
        printf '\n%s\n' "$XCOMPOSE_BLOCK" >> "$XCOMPOSE"
    fi
    ok ".XCompose updated"
fi

# --- environment.d -----------------------------------------------------------
ENV_DIR="$HOME/.config/environment.d"
ENV_FILE="$ENV_DIR/cedilla.conf"

if [[ -L "$ENV_FILE" ]]; then
    ok "environment.d/cedilla.conf is a symlink (managed by stow)"
elif [[ -f "$ENV_FILE" ]] && grep -q 'GTK_IM_MODULE=cedilla' "$ENV_FILE"; then
    ok "environment.d/cedilla.conf already configured"
else
    mkdir -p "$ENV_DIR"
    printf 'GTK_IM_MODULE=cedilla\nQT_IM_MODULE=cedilla\n' > "$ENV_FILE"
    ok "environment.d/cedilla.conf created"
fi

echo ""
info "Log out and back in for the changes to take effect in GUI apps."
info "To test immediately in this terminal:"
info "  export GTK_IM_MODULE=cedilla QT_IM_MODULE=cedilla"
