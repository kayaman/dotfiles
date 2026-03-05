#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  dotfiles uninstaller — restore backups
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

FILES=(
    "$HOME/.bashrc"
    "$HOME/.bash_aliases"
    "$HOME/.bash_functions"
    "$HOME/.blerc"
    "$HOME/.inputrc"
    "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
    "${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config"
    "$HOME/.gitconfig"
)

for file in "${FILES[@]}"; do
    if [[ -L "$file" ]]; then
        rm "$file"
        info "Removed symlink: $file"

        # Restore backup if one exists
        latest_backup="$(ls -t "${file}".bak.* 2>/dev/null | head -1)"
        if [[ -n "$latest_backup" ]]; then
            mv "$latest_backup" "$file"
            info "Restored backup: $latest_backup → $file"
        fi
    fi
done

echo ""
warn "System packages and tools (ble.sh, starship, fzf, etc.) were NOT removed."
warn "Remove them manually if desired."
echo ""
info "Done. Run 'exec bash' to reload."
