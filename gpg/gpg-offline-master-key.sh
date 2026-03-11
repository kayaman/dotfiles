#!/usr/bin/env bash
#
# gpg-offline-master-key.sh
# Moves your GPG master (primary) private key to a secure offline location
# (e.g. encrypted USB drive), leaving only subkeys on your daily machine.
#
# After running this script:
#   - Your master key exists ONLY on the backup media
#   - Your machine retains subkeys (Sign, Encrypt, Authenticate)
#   - `gpg --list-secret-keys` will show "sec#" (# = master key absent)
#   - Day-to-day operations (signing commits, encrypting files) still work
#   - Key certification, revoking subkeys, and editing the key require
#     re-importing the master from the backup
#
# Works on: openSUSE Tumbleweed, Ubuntu 22.04+, most modern Linux distros
# Usage: bash gpg-offline-master-key.sh

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Colors & helpers
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
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

confirm_or_die() {
    confirm "$1" || fatal "Aborted by user."
}

# ──────────────────────────────────────────────────────────────────────────────
# verify_file_exists_and_nonzero — abort the entire script if a backup file
# is missing or empty. This prevents proceeding to the destructive step with
# broken/absent backups.
# ──────────────────────────────────────────────────────────────────────────────
verify_file_exists_and_nonzero() {
    local filepath="$1"
    local label="$2"
    local min_bytes="${3:-100}"

    if [[ ! -f "$filepath" ]]; then
        fatal "${label} does not exist at: ${filepath}"
    fi

    local actual_size
    actual_size=$(stat --format='%s' "$filepath" 2>/dev/null || stat -f '%z' "$filepath" 2>/dev/null)

    if [[ -z "$actual_size" ]] || (( actual_size < min_bytes )); then
        fatal "${label} is suspiciously small (${actual_size:-0} bytes). Expected at least ${min_bytes}. Backup may be corrupt — aborting."
    fi

    success "${label} verified: ${filepath} (${actual_size} bytes)"
}

# ──────────────────────────────────────────────────────────────────────────────
# verify_not_shadowed_by_mount — detects the exact scenario that caused data
# loss: writing to a path like /mnt/gpg-backup that is a plain directory on
# the root filesystem, where a device COULD be mounted on top later, hiding
# everything written there.
#
# We check that the backup directory is on a different filesystem device than
# the root filesystem. If the path is /mnt/gpg-backup but nothing is mounted
# there, it lives on the root filesystem — which is almost certainly not the
# intended encrypted USB target.
# ──────────────────────────────────────────────────────────────────────────────
verify_not_shadowed_by_mount() {
    local dir="$1"

    # Get the device ID of the backup directory and the root filesystem
    local dir_device root_device
    dir_device=$(stat --format='%d' "$dir" 2>/dev/null || stat -f '%d' "$dir" 2>/dev/null)
    root_device=$(stat --format='%d' / 2>/dev/null || stat -f '%d' / 2>/dev/null)

    # Get the mount source for display
    local actual_source
    actual_source=$(df --output=source "$dir" 2>/dev/null | tail -1)
    local actual_mount
    actual_mount=$(df --output=target "$dir" 2>/dev/null | tail -1)

    info "Backup directory device:  ${actual_source} (mounted on ${actual_mount})"

    # CRITICAL CHECK: if a path looks like it should be on external media
    # (e.g. /mnt/*, /media/*) but is actually on the root filesystem,
    # the user likely forgot to mount their USB drive.
    case "$dir" in
        /mnt/*|/media/*|/run/media/*)
            if [[ "$dir_device" == "$root_device" ]]; then
                echo
                error "═══════════════════════════════════════════════════════════"
                error "  MOUNT POINT SAFETY CHECK FAILED"
                error "═══════════════════════════════════════════════════════════"
                error ""
                error "  Path:       ${dir}"
                error "  Lives on:   / (root filesystem)"
                error "  Expected:   a separate mounted device (e.g. USB drive)"
                error ""
                error "  This means no external device is mounted at this path."
                error "  Files written here would be hidden if a device is mounted"
                error "  on top later — which is exactly how keys get lost."
                error ""
                error "  Mount your encrypted USB drive first, then re-run."
                error "  Example:  sudo cryptsetup open /dev/sdX gpg-backup"
                error "            sudo mount /dev/mapper/gpg-backup /mnt/gpg-backup"
                error "═══════════════════════════════════════════════════════════"
                fatal "Backup destination is on the root filesystem. Refusing to continue."
            else
                success "Mount point check passed — ${dir} is on a separate device."
            fi
            ;;
        /tmp/*|/home/*)
            warn "Backup path is on your local filesystem — NOT secure for production use."
            warn "For real use, choose an encrypted USB drive or hardware token."
            confirm_or_die "Continue anyway (e.g. for testing)?"
            ;;
        *)
            # For other paths, check if it's on root and warn
            if [[ "$dir_device" == "$root_device" ]]; then
                warn "Backup path ${dir} is on the root filesystem."
                warn "If you intended to write to external media, mount it first."
                confirm_or_die "Continue writing to root filesystem?"
            fi
            ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────────
# Detect GPG binary (gpg2 on openSUSE, gpg on Ubuntu/others)
# ──────────────────────────────────────────────────────────────────────────────
if command -v gpg2 &>/dev/null; then
    GPG=gpg2
elif command -v gpg &>/dev/null; then
    GPG=gpg
else
    fatal "Neither gpg2 nor gpg found. Install gnupg first."
fi

GPG_VERSION=$($GPG --version | head -1)
info "Using: ${GPG} (${GPG_VERSION})"

GNUPG_HOME="${GNUPGHOME:-${HOME}/.gnupg}"

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Select the key to move offline
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  GPG Offline Master Key Migration${NC}\n"
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
echo
printf "${DIM}This script will:${NC}\n"
printf "${DIM}  1. Back up your entire ~/.gnupg directory${NC}\n"
printf "${DIM}  2. Export your master key + subkeys to a secure location${NC}\n"
printf "${DIM}  3. Export your revocation certificate${NC}\n"
printf "${DIM}  4. Remove the master private key from this machine${NC}\n"
printf "${DIM}  5. Keep only subkeys for daily use${NC}\n"
echo

info "Listing your secret keys:"
echo
$GPG --list-secret-keys --keyid-format long 2>/dev/null
echo

printf "${BOLD}Enter the key ID or email of the master key to move offline:${NC} "
read -r KEY_IDENTIFIER

if [[ -z "$KEY_IDENTIFIER" ]]; then
    fatal "No key specified."
fi

# Validate key exists and extract fingerprint
FINGERPRINT=$($GPG --list-secret-keys --with-colons "$KEY_IDENTIFIER" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')

if [[ -z "$FINGERPRINT" ]]; then
    fatal "No secret key found for '${KEY_IDENTIFIER}'."
fi

KEY_ID_LONG=$($GPG --list-secret-keys --keyid-format long --with-colons "$KEY_IDENTIFIER" 2>/dev/null \
    | awk -F: '/^sec:/ { split($5, a, ""); print $5; exit }')

# Show what we found
echo
info "Selected key:"
$GPG --list-secret-keys --keyid-format long "$FINGERPRINT" 2>/dev/null
echo
info "Fingerprint: ${FINGERPRINT}"

# Check if master key is already offline
SEC_LINE=$($GPG --list-secret-keys --with-colons "$FINGERPRINT" 2>/dev/null \
    | grep '^sec:' | head -1)
if echo "$SEC_LINE" | grep -q ':#:'; then
    fatal "Master key is already absent (offline). Nothing to do."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Choose the secure backup destination
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Choose backup destination ──${NC}\n"
echo
info "This should be a secure, offline location — typically an encrypted USB drive."
info "The directory must already exist and be writable."
echo
info "Example paths:"
info "  /media/\${USER}/ENCRYPTED_USB/gpg-master-backup"
info "  /run/media/\${USER}/GPG-BACKUP"
info "  /mnt/usb/gpg-master-backup"
info "  /tmp/gpg-master-backup  (for testing only — NOT secure!)"
echo

printf "${BOLD}Backup destination path:${NC} "
read -r BACKUP_DIR

if [[ -z "$BACKUP_DIR" ]]; then
    fatal "No backup directory specified."
fi

# Create if it doesn't exist
if [[ ! -d "$BACKUP_DIR" ]]; then
    info "Directory does not exist. Creating: ${BACKUP_DIR}"
    mkdir -p "$BACKUP_DIR" || fatal "Could not create ${BACKUP_DIR}."
fi

# Test writability
touch "${BACKUP_DIR}/.write_test" 2>/dev/null && rm -f "${BACKUP_DIR}/.write_test" \
    || fatal "Cannot write to ${BACKUP_DIR}."

# ──────────────────────────────────────────────────────────────────────────────
# SAFETY: Verify the backup destination is actually on a mounted device
# and not a directory on the root filesystem that will be shadowed later.
# ──────────────────────────────────────────────────────────────────────────────
verify_not_shadowed_by_mount "$BACKUP_DIR"

success "Backup destination: ${BACKUP_DIR}"

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Full backup of ~/.gnupg
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 1/5: Full backup of ${GNUPG_HOME} ──${NC}\n"
echo

GNUPG_BACKUP="${BACKUP_DIR}/gnupg-full-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
info "Creating full backup: ${GNUPG_BACKUP}"

tar czf "$GNUPG_BACKUP" -C "$(dirname "$GNUPG_HOME")" "$(basename "$GNUPG_HOME")" 2>/dev/null \
    && success "Full ~/.gnupg backup saved." \
    || fatal "Failed to back up ~/.gnupg."

chmod 600 "$GNUPG_BACKUP"

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Export master secret key (with subkeys)
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 2/5: Export master private key ──${NC}\n"
echo

MASTER_KEY_FILE="${BACKUP_DIR}/master-secret-key-${FINGERPRINT}.asc"
info "Exporting full secret key (master + subkeys)..."

$GPG --armor --export-secret-keys "$FINGERPRINT" > "$MASTER_KEY_FILE" 2>/dev/null \
    && success "Master secret key exported: ${MASTER_KEY_FILE}" \
    || fatal "Failed to export master secret key."

chmod 600 "$MASTER_KEY_FILE"

# Also export secret subkeys separately (useful for re-importing later)
SUBKEYS_FILE="${BACKUP_DIR}/secret-subkeys-${FINGERPRINT}.asc"
info "Exporting secret subkeys only..."

$GPG --armor --export-secret-subkeys "$FINGERPRINT" > "$SUBKEYS_FILE" 2>/dev/null \
    && success "Secret subkeys exported: ${SUBKEYS_FILE}" \
    || fatal "Failed to export secret subkeys."

chmod 600 "$SUBKEYS_FILE"

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Export public key
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 3/5: Export public key ──${NC}\n"
echo

PUBLIC_KEY_FILE="${BACKUP_DIR}/public-key-${FINGERPRINT}.asc"
info "Exporting public key..."

$GPG --armor --export "$FINGERPRINT" > "$PUBLIC_KEY_FILE" 2>/dev/null \
    && success "Public key exported: ${PUBLIC_KEY_FILE}" \
    || fatal "Failed to export public key."

# ──────────────────────────────────────────────────────────────────────────────
# Step 6: Copy revocation certificate
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 4/5: Copy revocation certificate ──${NC}\n"
echo

REVOKE_SRC="${GNUPG_HOME}/openpgp-revocs.d/${FINGERPRINT}.rev"
REVOKE_DST="${BACKUP_DIR}/revocation-cert-${FINGERPRINT}.rev"

if [[ -f "$REVOKE_SRC" ]]; then
    cp "$REVOKE_SRC" "$REVOKE_DST"
    chmod 600 "$REVOKE_DST"
    success "Revocation certificate copied: ${REVOKE_DST}"
else
    warn "No pre-generated revocation certificate found at ${REVOKE_SRC}."
    info "Generating one now..."
    $GPG --output "$REVOKE_DST" --gen-revoke "$FINGERPRINT" 2>/dev/null \
        && success "Revocation certificate generated: ${REVOKE_DST}" \
        || warn "Could not generate revocation certificate. Create one manually later."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 7: COMPREHENSIVE backup verification before deleting anything
#
# This is the critical safety gate. We verify:
#   1. Every backup file exists and has a sane minimum size
#   2. The exported key fingerprint matches the source
#   3. The backup content starts with valid PGP headers
#   4. The backup is still on the expected filesystem (race guard)
#   5. The tarball backup is not corrupt
# Only after ALL checks pass do we proceed to the destructive step.
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Backup verification (ALL checks must pass) ──${NC}\n"
echo

VERIFY_FAILURES=0

# 7a. Verify each file exists and has a reasonable size
# GPG armored secret key exports are typically > 500 bytes (Ed25519) or > 3000 (RSA)
verify_file_exists_and_nonzero "$GNUPG_BACKUP"   "Full gnupg backup tarball" 1000   || ((VERIFY_FAILURES++)) || true
verify_file_exists_and_nonzero "$MASTER_KEY_FILE" "Master secret key export"  500    || ((VERIFY_FAILURES++)) || true
verify_file_exists_and_nonzero "$SUBKEYS_FILE"    "Subkeys-only export"       200    || ((VERIFY_FAILURES++)) || true
verify_file_exists_and_nonzero "$PUBLIC_KEY_FILE"  "Public key export"        200    || ((VERIFY_FAILURES++)) || true

# 7b. Verify the exported key can be parsed and fingerprint matches
echo
info "Verifying exported key fingerprint..."
EXPORTED_FPR=$($GPG --with-colons --import-options show-only --import "$MASTER_KEY_FILE" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')

if [[ "$EXPORTED_FPR" == "$FINGERPRINT" ]]; then
    success "Fingerprint match: exported key matches source key."
else
    error "Fingerprint MISMATCH: expected ${FINGERPRINT}, got ${EXPORTED_FPR:-nothing}"
    ((VERIFY_FAILURES++)) || true
fi

# 7c. Read-back test: flush to disk, re-read the master key file, verify PGP header
info "Read-back test: confirming files are readable from disk..."
sync

READBACK_HEADER=$(head -1 "$MASTER_KEY_FILE" 2>/dev/null)
if [[ "$READBACK_HEADER" == "-----BEGIN PGP PRIVATE KEY BLOCK-----" ]]; then
    success "Read-back test passed: master key file contains valid PGP data."
else
    error "Read-back test FAILED: master key file header is: '${READBACK_HEADER:-<empty>}'"
    ((VERIFY_FAILURES++)) || true
fi

# 7d. Re-verify filesystem hasn't changed (USB unplugged during export?)
info "Re-checking backup destination filesystem..."
if [[ ! -d "$BACKUP_DIR" ]]; then
    error "Backup directory disappeared! Media may have been disconnected."
    ((VERIFY_FAILURES++)) || true
else
    RECHECK_DEVICE=$(stat --format='%d' "$BACKUP_DIR" 2>/dev/null || stat -f '%d' "$BACKUP_DIR" 2>/dev/null)
    ROOT_DEVICE=$(stat --format='%d' / 2>/dev/null || stat -f '%d' / 2>/dev/null)
    case "$BACKUP_DIR" in
        /mnt/*|/media/*|/run/media/*)
            if [[ "$RECHECK_DEVICE" == "$ROOT_DEVICE" ]]; then
                error "Backup directory is now on root filesystem — media may have been disconnected!"
                ((VERIFY_FAILURES++)) || true
            else
                success "Filesystem re-check passed."
            fi
            ;;
        *)
            success "Filesystem re-check passed."
            ;;
    esac
fi

# 7e. Verify the tarball backup can actually be listed (not corrupt)
info "Verifying tarball integrity..."
if tar tzf "$GNUPG_BACKUP" &>/dev/null; then
    success "Tarball integrity check passed."
else
    error "Tarball is corrupt or unreadable!"
    ((VERIFY_FAILURES++)) || true
fi

echo
info "Files in backup directory:"
ls -lh "$BACKUP_DIR"/ | grep -v '^total'
echo

# ──────────────────────────────────────────────────────────────────────────────
# GATE: If ANY verification failed, refuse to proceed
# ──────────────────────────────────────────────────────────────────────────────
if (( VERIFY_FAILURES > 0 )); then
    echo
    error "═══════════════════════════════════════════════════════════"
    error "  ${VERIFY_FAILURES} VERIFICATION CHECK(S) FAILED"
    error "  Refusing to proceed with key deletion."
    error "  Your keys are UNCHANGED on this machine."
    error "═══════════════════════════════════════════════════════════"
    fatal "Fix the issues above and re-run the script."
fi

printf "${GREEN}All verification checks passed.${NC}\n"

# ──────────────────────────────────────────────────────────────────────────────
# Step 8: Remove master private key, re-import subkeys only
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${RED}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}${RED}  DESTRUCTIVE STEP: Remove master key from this machine${NC}\n"
printf "${BOLD}${RED}══════════════════════════════════════════════════════════════${NC}\n"
echo
warn "This will DELETE the master private key from your local keyring."
warn "Only subkeys will remain for daily use (signing, encryption)."
warn "To use the master key again (certify other keys, add/revoke subkeys),"
warn "you will need to re-import from: ${MASTER_KEY_FILE}"
echo
info "Backup location: ${BACKUP_DIR}"
info "Backup device:   $(df --output=source "$BACKUP_DIR" 2>/dev/null | tail -1)"
echo

confirm_or_die "Have you PHYSICALLY verified the backup files on the external media?"
confirm_or_die "FINAL CONFIRMATION: Delete the master private key from this machine?"

echo
info "Removing ALL secret keys for this fingerprint from local keyring..."

# GPG won't let you delete just the master key directly.
# The standard approach is: delete all secret keys, then re-import subkeys only.
$GPG --batch --yes --delete-secret-keys "$FINGERPRINT" 2>/dev/null \
    && success "Secret keys removed from local keyring." \
    || fatal "Failed to delete secret keys. Your keys are unchanged."

info "Re-importing subkeys only..."
$GPG --batch --import "$SUBKEYS_FILE" 2>/dev/null \
    && success "Subkeys re-imported successfully." \
    || {
        error "Failed to re-import subkeys from ${SUBKEYS_FILE}!"
        error ""
        error "RECOVERY — run one of these commands:"
        error "  ${GPG} --import ${MASTER_KEY_FILE}"
        error "  OR restore full backup:"
        error "  rm -rf ~/.gnupg && tar xzf ${GNUPG_BACKUP} -C ~/"
        fatal "Subkey import failed."
    }

# ──────────────────────────────────────────────────────────────────────────────
# Step 9: Verify the result
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 5/5: Verification ──${NC}\n"
echo

info "Current secret keys on this machine:"
echo
$GPG --list-secret-keys --keyid-format long "$FINGERPRINT" 2>/dev/null
echo

# Check for "sec#" which indicates master key is absent
SEC_CHECK=$($GPG --list-secret-keys --with-colons "$FINGERPRINT" 2>/dev/null \
    | grep '^sec:' | head -1)

if echo "$SEC_CHECK" | grep -q ':#:'; then
    success "Master key is now OFFLINE (sec# — stub only)."
else
    # Some GPG versions show it differently — check the human-readable output
    HUMAN_CHECK=$($GPG --list-secret-keys "$FINGERPRINT" 2>/dev/null | head -5)
    if echo "$HUMAN_CHECK" | grep -q 'sec#'; then
        success "Master key is now OFFLINE (sec# — stub only)."
    else
        warn "Could not confirm master key removal. Check manually:"
        warn "  ${GPG} --list-secret-keys ${FINGERPRINT}"
        warn "Look for 'sec#' — the '#' means the master key is absent."
    fi
fi

# Quick functional test — can we still sign?
echo
info "Testing subkey signing capability..."
TEST_SIG=$(echo "test" | $GPG --sign --armor --local-user "$FINGERPRINT" 2>/dev/null) && {
    success "Signing with subkey works — Git commit signing will continue to work."
} || {
    warn "Signing test failed. This might be a pinentry issue in the current terminal."
    warn "Try manually: echo 'test' | ${GPG} --sign --armor --local-user ${FINGERPRINT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}${GREEN}  Migration complete!${NC}\n"
printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
echo
info "Master key fingerprint: ${FINGERPRINT}"
info "Master key status:      OFFLINE (removed from this machine)"
info "Subkeys status:         ACTIVE (available for daily use)"
echo
info "Backup contents (${BACKUP_DIR}):"
info "  ${GNUPG_BACKUP##*/}       — full ~/.gnupg snapshot"
info "  ${MASTER_KEY_FILE##*/}    — master + subkey private keys"
info "  ${SUBKEYS_FILE##*/}       — subkeys only"
info "  ${PUBLIC_KEY_FILE##*/}    — public key"
info "  ${REVOKE_DST##*/}        — revocation certificate"
echo
printf "${BOLD}What still works on this machine:${NC}\n"
info "  ✔ Signing Git commits and tags"
info "  ✔ Encrypting and decrypting files"
info "  ✔ SSH authentication (if using a GPG auth subkey)"
echo
printf "${BOLD}What requires the master key (from backup):${NC}\n"
info "  ✘ Signing (certifying) other people's keys"
info "  ✘ Adding or revoking subkeys"
info "  ✘ Changing the key's expiration date"
info "  ✘ Adding new UIDs (email addresses)"
echo
printf "${BOLD}To temporarily restore the master key:${NC}\n"
info "  ${GPG} --import ${MASTER_KEY_FILE}"
info "  # ... do your operation ..."
info "  # Then re-run this script to move it offline again"
echo
printf "${BOLD}${RED}IMPORTANT:${NC} Safely eject/unmount the backup media now.\n"
printf "${BOLD}${RED}IMPORTANT:${NC} Store it in a physically secure location.\n"
echo
