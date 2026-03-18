#!/usr/bin/env bash
#
# remove-gpg-keys.sh
# Safely removes specified or all GPG keys from the system, cleans up associated
# files, and updates Git configuration if any deleted key matches the signing key.
#
# Usage:
#   remove-gpg-keys.sh [OPTIONS] [KEY_IDENTIFIER...]
#   remove-gpg-keys.sh --all [OPTIONS]
#
# Options:
#   --all            Remove all GPG keys from the system
#   --dry-run        Show what would be deleted without making changes
#   --force          Skip interactive confirmations
#   --help, -h       Show this help message
#
# Key Identifiers:
#   - Full fingerprint (40 chars)
#   - Key ID (8 or 16 chars)
#   - Email address
#   - User ID string
#
# Examples:
#   remove-gpg-keys.sh user@example.com
#   remove-gpg-keys.sh 8237E64F98A71AD8
#   remove-gpg-keys.sh --all --force
#   remove-gpg-keys.sh --dry-run --all
#

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
    if [[ "$FORCE_MODE" == "true" ]]; then
        info "Force mode: assuming yes to: $prompt"
        return 0
    fi
    printf "${BOLD}%s [y/N]${NC} " "$prompt" >&2
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Global variables
# ──────────────────────────────────────────────────────────────────────────────
DRY_RUN=false
FORCE_MODE=false
REMOVE_ALL=false
KEY_IDENTIFIERS=()

# ──────────────────────────────────────────────────────────────────────────────
# Detect GPG binary and dependencies
# ──────────────────────────────────────────────────────────────────────────────
if command -v gpg2 &>/dev/null; then
    GPG=gpg2
elif command -v gpg &>/dev/null; then
    GPG=gpg
else
    fatal "Neither gpg2 nor gpg found. Install gnupg first."
fi

# Dependency check
MISSING=()
for cmd in $GPG git; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if (( ${#MISSING[@]} > 0 )); then
    fatal "Missing required commands: ${MISSING[*]}. Install them and re-run."
fi

GPG_VER_FULL=$($GPG --version | head -1 | awk '{print $3}')
info "Using: ${GPG} (${GPG_VER_FULL})"

# ──────────────────────────────────────────────────────────────────────────────
# Key identification and listing functions
# ──────────────────────────────────────────────────────────────────────────────
get_all_key_fingerprints() {
    local key_type="$1"  # "public" or "secret"
    local fingerprints=()
    
    local cmd="--list-keys"
    [[ "$key_type" == "secret" ]] && cmd="--list-secret-keys"
    
    while IFS= read -r fpr; do
        [[ -n "$fpr" ]] && fingerprints+=("$fpr")
    done < <($GPG $cmd --with-colons 2>/dev/null | awk -F: '/^fpr:/ { print $10 }')
    
    printf '%s\n' "${fingerprints[@]}"
}

resolve_key_identifier() {
    local identifier="$1"
    local fingerprints=()
    
    # Try to find matching keys using the identifier
    while IFS= read -r line; do
        [[ -n "$line" ]] && fingerprints+=("$line")
    done < <($GPG --list-keys --with-colons "$identifier" 2>/dev/null | awk -F: '/^fpr:/ { print $10 }')
    
    printf '%s\n' "${fingerprints[@]}"
}

get_key_info() {
    local fingerprint="$1"
    local uid email keyid
    
    # Get key info using fingerprint
    local key_data
    key_data=$($GPG --list-keys --with-colons "$fingerprint" 2>/dev/null || true)
    
    if [[ -z "$key_data" ]]; then
        echo "INVALID_KEY"
        return 1
    fi
    
    uid=$(echo "$key_data" | awk -F: '/^uid:/ { print $10; exit }')
    keyid=$(echo "$key_data" | awk -F: '/^pub:/ { print $5; exit }')
    email=$(echo "$uid" | sed -n 's/.*<\(.*\)>.*/\1/p')
    
    printf "KEYID:%s|UID:%s|EMAIL:%s" "$keyid" "$uid" "${email:-N/A}"
}

list_keys_for_deletion() {
    local -a fingerprints=("$@")
    
    if (( ${#fingerprints[@]} == 0 )); then
        warn "No keys found to delete."
        return 1
    fi
    
    echo
    info "Keys to be deleted:"
    echo
    
    local i=1
    for fpr in "${fingerprints[@]}"; do
        local key_info
        key_info=$(get_key_info "$fpr")
        
        if [[ "$key_info" == "INVALID_KEY" ]]; then
            warn "Invalid key: $fpr"
            continue
        fi
        
        local keyid uid email
        keyid=$(echo "$key_info" | cut -d'|' -f1 | cut -d':' -f2)
        uid=$(echo "$key_info" | cut -d'|' -f2 | cut -d':' -f2)
        email=$(echo "$key_info" | cut -d'|' -f3 | cut -d':' -f2)
        
        # Check if it's a secret key
        local key_type="public"
        if $GPG --list-secret-keys "$fpr" &>/dev/null; then
            key_type="secret"
        fi
        
        printf "  ${BOLD}[%d]${NC} %s (%s)\n" "$i" "$uid" "$key_type"
        printf "       Key ID: ${DIM}%s${NC}\n" "$keyid"
        printf "       Email:  ${DIM}%s${NC}\n" "$email"
        printf "       Fingerprint: ${DIM}%s${NC}\n" "$fpr"
        echo
        ((i++))
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# Key deletion functions
# ──────────────────────────────────────────────────────────────────────────────
delete_secret_key() {
    local fingerprint="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete secret key: ${fingerprint:0:16}..."
        return 0
    fi
    
    if $GPG --batch --yes --delete-secret-keys "$fingerprint" 2>/dev/null; then
        success "Deleted secret key: ${fingerprint:0:16}..."
        return 0
    else
        warn "Failed to delete secret key: ${fingerprint:0:16}..."
        return 1
    fi
}

delete_public_key() {
    local fingerprint="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete public key: ${fingerprint:0:16}..."
        return 0
    fi
    
    if $GPG --batch --yes --delete-keys "$fingerprint" 2>/dev/null; then
        success "Deleted public key: ${fingerprint:0:16}..."
        return 0
    else
        warn "Failed to delete public key: ${fingerprint:0:16}..."
        return 1
    fi
}

delete_gpg_key() {
    local fingerprint="$1"
    local has_secret=false
    local has_public=false
    
    # Check what we have
    if $GPG --list-secret-keys "$fingerprint" &>/dev/null; then
        has_secret=true
    fi
    
    if $GPG --list-keys "$fingerprint" &>/dev/null; then
        has_public=true
    fi
    
    # Delete in proper order: secret first, then public
    local success_count=0
    local total_count=0
    
    if [[ "$has_secret" == "true" ]]; then
        ((total_count++))
        if delete_secret_key "$fingerprint"; then
            ((success_count++))
        fi
    fi
    
    if [[ "$has_public" == "true" ]]; then
        ((total_count++))
        if delete_public_key "$fingerprint"; then
            ((success_count++))
        fi
    fi
    
    if (( success_count == total_count )); then
        return 0
    else
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Git configuration cleanup
# ──────────────────────────────────────────────────────────────────────────────
cleanup_git_config() {
    local -a deleted_fingerprints=("$@")
    
    local git_signing_key
    git_signing_key=$(git config --global user.signingkey 2>/dev/null || true)
    
    if [[ -z "$git_signing_key" ]]; then
        info "No Git signing key configured."
        return 0
    fi
    
    info "Current Git signing key: $git_signing_key"
    
    # Check if any deleted key matches the Git signing key
    local match_found=false
    local matched_fpr=""
    
    for fpr in "${deleted_fingerprints[@]}"; do
        local key_info
        key_info=$(get_key_info "$fpr" 2>/dev/null || echo "INVALID_KEY")
        
        if [[ "$key_info" == "INVALID_KEY" ]]; then
            continue
        fi
        
        local keyid
        keyid=$(echo "$key_info" | cut -d'|' -f1 | cut -d':' -f2)
        
        # Match on key ID (last 8 or 16 chars) or full fingerprint
        if [[ "$git_signing_key" == "$keyid" ]] || \
           [[ "$git_signing_key" == "${keyid: -8}" ]] || \
           [[ "$git_signing_key" == "${keyid: -16}" ]] || \
           [[ "$git_signing_key" == "$fpr" ]]; then
            match_found=true
            matched_fpr="$fpr"
            break
        fi
    done
    
    if [[ "$match_found" == "false" ]]; then
        info "Git signing key does not match any deleted keys."
        return 0
    fi
    
    warn "Git signing key ($git_signing_key) matches deleted key: ${matched_fpr:0:16}..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would remove user.signingkey from Git config"
        info "[DRY-RUN] Would ask to disable commit.gpgsign"
        return 0
    fi
    
    if confirm "Remove user.signingkey from Git config?"; then
        git config --global --unset user.signingkey
        success "Removed user.signingkey from Git config."
        
        if confirm "Disable commit.gpgsign and tag.gpgsign?"; then
            git config --global commit.gpgsign false
            git config --global tag.gpgsign false
            success "Disabled GPG signing in Git config."
        fi
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# File cleanup functions
# ──────────────────────────────────────────────────────────────────────────────
cleanup_gpg_files() {
    local -a deleted_fingerprints=("$@")
    
    if [[ ! -d "${HOME}/.gnupg" ]]; then
        info "No .gnupg directory found."
        return 0
    fi
    
    info "Cleaning up GPG files..."
    
    # Clean up backup files
    local backup_files=(
        "${HOME}/.gnupg/pubring.kbx~"
        "${HOME}/.gnupg/pubring.gpg~"
        "${HOME}/.gnupg/secring.gpg~"
        "${HOME}/.gnupg/trustdb.gpg~"
    )
    
    for backup_file in "${backup_files[@]}"; do
        if [[ -f "$backup_file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY-RUN] Would remove backup file: $backup_file"
            else
                rm -f "$backup_file" && success "Removed backup file: $(basename "$backup_file")"
            fi
        fi
    done
    
    # Clean up revocation certificates for deleted keys
    if [[ -d "${HOME}/.gnupg/openpgp-revocs.d" ]]; then
        for fpr in "${deleted_fingerprints[@]}"; do
            local revoc_file="${HOME}/.gnupg/openpgp-revocs.d/${fpr}.rev"
            if [[ -f "$revoc_file" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY-RUN] Would remove revocation certificate: ${fpr:0:16}..."
                else
                    rm -f "$revoc_file" && success "Removed revocation certificate: ${fpr:0:16}..."
                fi
            fi
        done
    fi
    
    # If no keys remain, offer to clean the entire .gnupg directory
    local remaining_keys
    remaining_keys=$(get_all_key_fingerprints "public" | wc -l)
    
    if (( remaining_keys == 0 )); then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] No keys remaining - would ask to remove entire .gnupg directory"
            return 0
        fi
        
        if confirm "No GPG keys remaining. Remove entire .gnupg directory?"; then
            rm -rf "${HOME}/.gnupg" && success "Removed .gnupg directory completely."
        else
            # Just rebuild the trustdb
            $GPG --check-trustdb 2>/dev/null || true
            info "Rebuilt trust database."
        fi
    else
        # Rebuild trust database
        if [[ "$DRY_RUN" == "false" ]]; then
            $GPG --check-trustdb 2>/dev/null || true
            info "Rebuilt trust database."
        fi
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Command line interface
# ──────────────────────────────────────────────────────────────────────────────
show_help() {
    cat << 'EOF'
Usage: remove-gpg-keys.sh [OPTIONS] [KEY_IDENTIFIER...]
       remove-gpg-keys.sh --all [OPTIONS]

Safely removes specified or all GPG keys from the system, cleans up associated
files, and updates Git configuration if any deleted key matches the signing key.

Options:
  --all            Remove all GPG keys from the system
  --dry-run        Show what would be deleted without making changes
  --force          Skip interactive confirmations
  --help, -h       Show this help message

Key Identifiers:
  - Full fingerprint (40 characters)
  - Key ID (8 or 16 characters)  
  - Email address
  - User ID string

Examples:
  remove-gpg-keys.sh user@example.com
  remove-gpg-keys.sh 8237E64F98A71AD8
  remove-gpg-keys.sh --all --force
  remove-gpg-keys.sh --dry-run --all
  remove-gpg-keys.sh --dry-run user@example.com

Safety Notes:
  - Secret keys are deleted before public keys
  - Git configuration is updated if signing key matches deleted key
  - Associated files (private keys, revocation certificates) are cleaned up
  - Use --dry-run to preview changes before making them
EOF
}

parse_arguments() {
    while (( $# > 0 )); do
        case "$1" in
            --all)
                REMOVE_ALL=true
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --force)
                FORCE_MODE=true
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                fatal "Unknown option: $1. Use --help for usage."
                ;;
            *)
                KEY_IDENTIFIERS+=("$1")
                ;;
        esac
        shift
    done
    
    # Validate arguments
    if [[ "$REMOVE_ALL" == "true" ]] && (( ${#KEY_IDENTIFIERS[@]} > 0 )); then
        fatal "Cannot specify both --all and specific key identifiers."
    fi
    
    if [[ "$REMOVE_ALL" == "false" ]] && (( ${#KEY_IDENTIFIERS[@]} == 0 )); then
        fatal "Must specify either --all or key identifiers. Use --help for usage."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main execution
# ──────────────────────────────────────────────────────────────────────────────
main() {
    parse_arguments "$@"
    
    echo
    printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "${BOLD}  GPG Key Removal Script (DRY RUN MODE)${NC}\n"
    else
        printf "${BOLD}  GPG Key Removal Script${NC}\n"
    fi
    printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
    echo
    
    # Collect fingerprints to delete
    local -a target_fingerprints=()
    
    if [[ "$REMOVE_ALL" == "true" ]]; then
        info "Collecting all GPG keys for removal..."
        while IFS= read -r fpr; do
            [[ -n "$fpr" ]] && target_fingerprints+=("$fpr")
        done < <(get_all_key_fingerprints "public")
    else
        info "Resolving key identifiers..."
        for identifier in "${KEY_IDENTIFIERS[@]}"; do
            local resolved_fingerprints
            resolved_fingerprints=$(resolve_key_identifier "$identifier")
            
            if [[ -z "$resolved_fingerprints" ]]; then
                warn "No keys found for identifier: $identifier"
                continue
            fi
            
            while IFS= read -r fpr; do
                [[ -n "$fpr" ]] && target_fingerprints+=("$fpr")
            done <<< "$resolved_fingerprints"
        done
    fi
    
    # Remove duplicates from target_fingerprints
    local -a unique_fingerprints=()
    for fpr in "${target_fingerprints[@]}"; do
        local found=false
        for existing in "${unique_fingerprints[@]}"; do
            if [[ "$fpr" == "$existing" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == "false" ]] && unique_fingerprints+=("$fpr")
    done
    target_fingerprints=("${unique_fingerprints[@]}")
    
    if (( ${#target_fingerprints[@]} == 0 )); then
        warn "No keys found to delete."
        exit 1
    fi
    
    # List keys and confirm
    list_keys_for_deletion "${target_fingerprints[@]}"
    
    local action="delete"
    [[ "$DRY_RUN" == "true" ]] && action="would delete"
    
    if ! confirm "Proceed to $action ${#target_fingerprints[@]} GPG key(s)?"; then
        info "Operation cancelled."
        exit 0
    fi
    
    echo
    info "Starting key deletion..."
    
    # Delete keys
    local -a deleted_fingerprints=()
    local -a failed_fingerprints=()
    
    for fpr in "${target_fingerprints[@]}"; do
        if delete_gpg_key "$fpr"; then
            deleted_fingerprints+=("$fpr")
        else
            failed_fingerprints+=("$fpr")
        fi
    done
    
    # Report results
    echo
    if (( ${#deleted_fingerprints[@]} > 0 )); then
        success "Successfully deleted ${#deleted_fingerprints[@]} key(s)."
        
        # Clean up Git configuration
        cleanup_git_config "${deleted_fingerprints[@]}"
        
        # Clean up files
        cleanup_gpg_files "${deleted_fingerprints[@]}"
    fi
    
    if (( ${#failed_fingerprints[@]} > 0 )); then
        warn "Failed to delete ${#failed_fingerprints[@]} key(s):"
        for fpr in "${failed_fingerprints[@]}"; do
            warn "  ${fpr:0:16}..."
        done
    fi
    
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run completed. No actual changes were made."
    else
        printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
        printf "${BOLD}${GREEN}  GPG key removal completed!${NC}\n"
        printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    fi
    echo
    
    # Show remaining keys
    local remaining_keys
    remaining_keys=$(get_all_key_fingerprints "public" | wc -l)
    info "Remaining GPG keys: $remaining_keys"
    
    if (( remaining_keys > 0 )) && [[ "$DRY_RUN" == "false" ]]; then
        echo
        info "Current keyring state:"
        $GPG --list-keys --keyid-format long 2>/dev/null || info "(no keys found)"
    fi
}

# Run main function with all arguments
main "$@"