#!/usr/bin/env bash
#
# setup-ssh-github.sh
# Sets up an SSH key for GitHub — either generates a new Ed25519 key or
# uses an existing one. Uploads the public key via the GitHub API and
# configures ~/.ssh/config.
#
# Requirements:
#   - GitHub Personal Access Token (classic) with scope: admin:public_key
#
# Works on: openSUSE Tumbleweed, Ubuntu 22.04+, most modern Linux distros
# Usage: bash setup-ssh-github.sh

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

prompt_input() {
    local prompt="$1" var_name="$2" secret="${3:-false}"
    while true; do
        if [[ "$secret" == "true" ]]; then
            printf "${BOLD}%s${NC} " "$prompt" >&2
            read -rs "$var_name"
            echo >&2
        else
            printf "${BOLD}%s${NC} " "$prompt" >&2
            read -r "$var_name"
        fi
        [[ -n "${!var_name}" ]] && break
        warn "Input cannot be empty."
    done
}

confirm() {
    local prompt="${1:-Continue?}"
    printf "${BOLD}%s [y/N]${NC} " "$prompt" >&2
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Dependency check (no auto-install — just tell the user what's missing)
# ──────────────────────────────────────────────────────────────────────────────
MISSING=()
for cmd in ssh-keygen curl jq; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if (( ${#MISSING[@]} > 0 )); then
    fatal "Missing required commands: ${MISSING[*]}. Install them and re-run."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Banner
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  SSH Key Setup for GitHub${NC}\n"
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
echo

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Choose — new key or existing key
# ──────────────────────────────────────────────────────────────────────────────
printf "${BOLD}${YELLOW}── Step 1: SSH Key ──${NC}\n"
echo

# List existing Ed25519 keys
EXISTING_KEYS=()
while IFS= read -r -d '' keyfile; do
    EXISTING_KEYS+=("$keyfile")
done < <(find "${HOME}/.ssh" -maxdepth 1 -name '*.pub' -print0 2>/dev/null)

if (( ${#EXISTING_KEYS[@]} > 0 )); then
    info "Existing SSH public keys found:"
    echo
    for i in "${!EXISTING_KEYS[@]}"; do
        local_key="${EXISTING_KEYS[$i]}"
        key_type=$(awk '{print $1}' "$local_key" 2>/dev/null)
        key_comment=$(awk '{print $3}' "$local_key" 2>/dev/null)
        printf "  ${BOLD}[%d]${NC} %s (%s) %s\n" "$((i+1))" "$(basename "$local_key" .pub)" "$key_type" "$key_comment"
    done
    echo
    printf "  ${BOLD}[N]${NC} Generate a new Ed25519 key\n"
    echo

    printf "${BOLD}Choose [1-%d or N]:${NC} " "${#EXISTING_KEYS[@]}"
    read -r CHOICE

    if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
        USE_EXISTING=false
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#EXISTING_KEYS[@]} )); then
        USE_EXISTING=true
        SELECTED_PUB="${EXISTING_KEYS[$((CHOICE-1))]}"
        SSH_KEY_PATH="${SELECTED_PUB%.pub}"
    else
        fatal "Invalid selection."
    fi
else
    info "No existing SSH keys found in ~/.ssh/"
    USE_EXISTING=false
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 1a: Generate new key if needed
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$USE_EXISTING" == "false" ]]; then
    echo
    prompt_input "Email for SSH key comment:" SSH_COMMENT

    SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_github"

    if [[ -f "$SSH_KEY_PATH" ]]; then
        warn "Key already exists at ${SSH_KEY_PATH}."
        if confirm "Use a different filename?"; then
            prompt_input "Key filename (will be saved in ~/.ssh/):" SSH_FILENAME
            SSH_KEY_PATH="${HOME}/.ssh/${SSH_FILENAME}"
        else
            confirm "Overwrite ${SSH_KEY_PATH}?" || fatal "Aborted."
            # Remove old key before ssh-keygen to avoid double prompt
            rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
        fi
    fi

    echo
    info "Generating SSH Ed25519 keypair..."
    info "You will be prompted for an optional passphrase."
    echo

    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$SSH_KEY_PATH" \
        && success "SSH key generated: ${SSH_KEY_PATH}" \
        || fatal "SSH key generation failed."
fi

SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")
info "Public key: ${SSH_PUB_KEY}"

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Configure ~/.ssh/config
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 2: SSH Config ──${NC}\n"
echo

SSH_CONFIG="${HOME}/.ssh/config"
GITHUB_BLOCK="# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ${SSH_KEY_PATH}
    IdentitiesOnly yes
    AddKeysToAgent yes"

if [[ -f "$SSH_CONFIG" ]] && grep -q 'Host github.com' "$SSH_CONFIG"; then
    info "GitHub entry already exists in ${SSH_CONFIG}."
    if confirm "Replace the existing GitHub SSH config block?"; then
        # Remove old block (from "# GitHub" or "Host github.com" to next Host or EOF)
        cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
        info "Backup: ${SSH_CONFIG}.bak"

        awk '
            /^# GitHub$/     { skip=1; next }
            /^Host github\.com$/ { skip=1; next }
            skip && /^Host /  { skip=0 }
            skip && /^# /     { skip=0 }
            !skip             { print }
        ' "${SSH_CONFIG}.bak" > "$SSH_CONFIG"

        {
            [[ -s "$SSH_CONFIG" ]] && echo ""
            echo "$GITHUB_BLOCK"
        } >> "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        success "SSH config updated with new GitHub block."
    else
        warn "Skipping SSH config update. You may need to update IdentityFile manually."
    fi
else
    {
        [[ -f "$SSH_CONFIG" && -s "$SSH_CONFIG" ]] && echo ""
        echo "$GITHUB_BLOCK"
    } >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    success "SSH config created: ${SSH_CONFIG}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Add to SSH agent
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 3: SSH Agent ──${NC}\n"
echo

eval "$(ssh-agent -s)" &>/dev/null
ssh-add "$SSH_KEY_PATH" 2>/dev/null \
    && success "Key added to SSH agent." \
    || warn "Could not add key to agent. You may need to enter passphrase manually."

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Upload to GitHub
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 4: Upload to GitHub ──${NC}\n"
echo

if confirm "Upload this SSH key to GitHub via API?"; then
    prompt_input "GitHub Personal Access Token (scope: admin:public_key):" GH_TOKEN true

    SSH_TITLE="$(hostname)-$(date +%Y%m%d)-$(basename "$SSH_KEY_PATH")"
    info "Key title: ${SSH_TITLE}"

    HTTP_CODE=$(curl -s -o /tmp/gh_ssh_resp.json -w '%{http_code}' \
        -X POST "https://api.github.com/user/keys" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "$(jq -n --arg title "$SSH_TITLE" --arg key "$SSH_PUB_KEY" \
            '{title: $title, key: $key}')")

    case "$HTTP_CODE" in
        201) success "SSH key uploaded to GitHub." ;;
        422) warn "SSH key already exists on GitHub (duplicate). No action needed." ;;
        401) error "Authentication failed. Check your token and scopes." ;;
        *)   error "Upload failed (HTTP ${HTTP_CODE})."; cat /tmp/gh_ssh_resp.json >&2 ;;
    esac
    rm -f /tmp/gh_ssh_resp.json
else
    echo
    info "Add the key manually at: https://github.com/settings/ssh/new"
    echo
    printf "${DIM}%s${NC}\n" "$SSH_PUB_KEY"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Test connection
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 5: Verify ──${NC}\n"
echo

info "Testing SSH connection to GitHub..."
SSH_OUTPUT=$(ssh -T git@github.com -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 2>&1 || true)

if echo "$SSH_OUTPUT" | grep -qi "successfully authenticated"; then
    success "SSH authentication to GitHub works!"
else
    warn "SSH test output: ${SSH_OUTPUT}"
    info "If you just uploaded the key, try again in a moment: ssh -T git@github.com"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}${GREEN}  SSH setup complete!${NC}\n"
printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
echo
info "Private key:  ${SSH_KEY_PATH}"
info "Public key:   ${SSH_KEY_PATH}.pub"
echo
info "After reboot, re-add to agent:"
info "  eval \"\$(ssh-agent -s)\" && ssh-add ${SSH_KEY_PATH}"
echo
