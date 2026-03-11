#!/usr/bin/env bash

# gpg-restore-master-key.sh
# Temporarily restores an offline GPG master key for administrative operations
# (certifying other keys, adding/revoking subkeys, changing expiry, adding UIDs).
#
# After you're done, re-run gpg-offline-master-key.sh to move it offline again.
#
# Usage: bash gpg-restore-master-key.sh /path/to/master-secret-key-<FINGERPRINT>.asc

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Colors & helpers
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
success() { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
fatal()   { error "$*"; exit 1; }

confirm() {
    local prompt="${1:-Continue?}"
    printf "${BOLD}%s [y/N]${NC} " "$prompt" >&2
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Detect GPG binary
# ──────────────────────────────────────────────────────────────────────────────
if command -v gpg2 &>/dev/null; then
    GPG=gpg2
elif command -v gpg &>/dev/null; then
    GPG=gpg
else
    fatal "Neither gpg2 nor gpg found."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Validate input
# ──────────────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/master-secret-key-<FINGERPRINT>.asc"
    echo
    echo "This restores your offline master key temporarily."
    echo "After completing admin operations, re-run gpg-offline-master-key.sh"
    echo "to move the master key back offline."
    exit 1
fi

MASTER_KEY_FILE="$1"

if [[ ! -f "$MASTER_KEY_FILE" ]]; then
    fatal "File not found: ${MASTER_KEY_FILE}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Preview what we're importing
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}══════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  Restore Offline Master Key${NC}\n"
printf "${BOLD}══════════════════════════════════════════════════════${NC}\n"
echo

info "Inspecting key file: ${MASTER_KEY_FILE}"
echo
$GPG --import-options show-only --import "$MASTER_KEY_FILE" 2>/dev/null
echo

FINGERPRINT=$($GPG --with-colons --import-options show-only --import "$MASTER_KEY_FILE" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')

info "Fingerprint: ${FINGERPRINT}"
echo

# ──────────────────────────────────────────────────────────────────────────────
# Import the master key
# ──────────────────────────────────────────────────────────────────────────────
warn "This will restore the master private key to your local keyring."
warn "Remember to move it offline again when you're done."
echo

confirm "Import the master key now?" || exit 0

echo
$GPG --import "$MASTER_KEY_FILE" 2>&1
echo

# Verify
SEC_CHECK=$($GPG --list-secret-keys --with-colons "$FINGERPRINT" 2>/dev/null \
    | grep '^sec:' | head -1)

if echo "$SEC_CHECK" | grep -q ':#:'; then
    warn "Master key still shows as absent. The import may not have worked."
    warn "Check manually: ${GPG} --list-secret-keys ${FINGERPRINT}"
else
    success "Master key restored to local keyring."
fi

echo
info "Current key status:"
$GPG --list-secret-keys --keyid-format long "$FINGERPRINT" 2>/dev/null
echo

# ──────────────────────────────────────────────────────────────────────────────
# Guidance
# ──────────────────────────────────────────────────────────────────────────────
printf "${BOLD}You can now perform admin operations:${NC}\n"
echo
info "  Sign someone's key:      ${GPG} --sign-key THEIR_KEY_ID"
info "  Add a new UID:           ${GPG} --edit-key ${FINGERPRINT}  →  adduid"
info "  Add a new subkey:        ${GPG} --edit-key ${FINGERPRINT}  →  addkey"
info "  Revoke a subkey:         ${GPG} --edit-key ${FINGERPRINT}  →  key N  →  revkey"
info "  Change expiration:       ${GPG} --edit-key ${FINGERPRINT}  →  expire"
info "  Generate revocation:     ${GPG} --gen-revoke ${FINGERPRINT}"
echo
printf "${BOLD}${RED}When done, re-run gpg-offline-master-key.sh to move the master key offline again.${NC}\n"
echo
