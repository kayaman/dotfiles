#!/usr/bin/env bash
#
# setup-gpg-github.sh
# Sets up a GPG key for GitHub commit signing — either generates a new
# Ed25519/RSA key or uses an existing one. Uploads the public key via the
# GitHub API and configures ~/.gitconfig.
#
# Flags:
#   --cleanup    Interactively remove orphaned keys (no private key) and
#                corrupted entries from your GPG keyring. Does NOT touch
#                keys that have valid secret keys.
#
# Requirements:
#   - GitHub Personal Access Token (classic) with scope: admin:gpg_key
#
# Works on: openSUSE Tumbleweed, Ubuntu 22.04+, most modern Linux distros
# Usage:
#   bash setup-gpg-github.sh              # Normal setup
#   bash setup-gpg-github.sh --cleanup    # Clean orphaned keys, then setup

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

info() { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
success() { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
fatal() {
  error "$*"
  exit 1
}

prompt_input() {
  local prompt="$1" var_name="$2" secret="${3:-false}"
  while true; do
    if [[ "$secret" == "true" ]]; then
      printf "${BOLD}%s${NC} " "$prompt" >&2
      read -rs "${var_name?}"
      echo >&2
    else
      printf "${BOLD}%s${NC} " "$prompt" >&2
      read -r "${var_name?}"
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
# Detect GPG binary
# ──────────────────────────────────────────────────────────────────────────────
if command -v gpg2 &> /dev/null; then
  GPG=gpg2
elif command -v gpg &> /dev/null; then
  GPG=gpg
else
  fatal "Neither gpg2 nor gpg found. Install gnupg first."
fi

# Dependency check
MISSING=()
for cmd in $GPG curl jq git; do
  command -v "$cmd" &> /dev/null || MISSING+=("$cmd")
done
if ((${#MISSING[@]} > 0)); then
  fatal "Missing required commands: ${MISSING[*]}. Install them and re-run."
fi

GPG_VER_FULL=$($GPG --version | head -1 | awk '{print $3}')
GPG_MAJOR=$(echo "$GPG_VER_FULL" | cut -d. -f1)
GPG_MINOR=$(echo "$GPG_VER_FULL" | cut -d. -f2)
info "Using: ${GPG} (${GPG_VER_FULL})"

# ──────────────────────────────────────────────────────────────────────────────
# --cleanup mode: remove orphaned / corrupted GPG keys
# ──────────────────────────────────────────────────────────────────────────────
run_cleanup() {
  echo
  printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
  printf "${BOLD}  GPG Keyring Cleanup${NC}\n"
  printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
  echo
  info "Scanning for orphaned keys (public keys without a matching private key)..."
  echo

  # Collect all public key fingerprints
  local all_pub_fprs=()
  while IFS= read -r fpr; do
    all_pub_fprs+=("$fpr")
  done < <($GPG --list-keys --with-colons 2> /dev/null \
    | awk -F: '/^fpr:/ { print $10 }')

  # Collect all secret key fingerprints
  local all_sec_fprs=()
  while IFS= read -r fpr; do
    all_sec_fprs+=("$fpr")
  done < <($GPG --list-secret-keys --with-colons 2> /dev/null \
    | awk -F: '/^fpr:/ { print $10 }')

  # Also collect "stub" secret keys (sec#) — these have no usable private key
  # but still show up in --list-secret-keys. We identify them by the '#' marker.
  local stub_fprs=()
  local current_fpr=""
  local is_stub=false
  while IFS= read -r line; do
    local field1 field10
    field1=$(echo "$line" | cut -d: -f1)
    field10=$(echo "$line" | cut -d: -f10)

    if [[ "$field1" == "sec" ]]; then
      is_stub=false
      # Check for '#' in the key capabilities/status
      # In --with-colons output, field 2 contains key status
      local field2
      field2=$(echo "$line" | cut -d: -f2)
      if [[ "$field2" == "#" ]]; then
        is_stub=true
      fi
    elif [[ "$field1" == "fpr" ]]; then
      current_fpr="$field10"
      if [[ "$is_stub" == "true" ]]; then
        stub_fprs+=("$current_fpr")
      fi
    fi
  done < <($GPG --list-secret-keys --with-colons 2> /dev/null)

  # Find orphans: public keys that have no corresponding secret key at all
  local orphan_fprs=()
  for pub_fpr in "${all_pub_fprs[@]}"; do
    local has_secret=false
    for sec_fpr in "${all_sec_fprs[@]}"; do
      if [[ "$pub_fpr" == "$sec_fpr" ]]; then
        has_secret=true
        break
      fi
    done
    if [[ "$has_secret" == "false" ]]; then
      orphan_fprs+=("$pub_fpr")
    fi
  done

  local total_issues=$((${#orphan_fprs[@]} + ${#stub_fprs[@]}))

  if ((total_issues == 0)); then
    success "Keyring is clean — no orphaned or stub keys found."
    echo
    return 0
  fi

  # Display orphaned keys (no private key at all)
  if ((${#orphan_fprs[@]} > 0)); then
    warn "Found ${#orphan_fprs[@]} public key(s) with NO private key:"
    echo
    for fpr in "${orphan_fprs[@]}"; do
      printf "  ${RED}[ORPHAN]${NC} "
      local uid
      uid=$($GPG --list-keys --with-colons "$fpr" 2> /dev/null \
        | awk -F: '/^uid:/ { print $10; exit }')
      printf "%s\n" "${uid:-<no UID>}"
      printf "           Fingerprint: ${DIM}%s${NC}\n" "$fpr"
    done
    echo
  fi

  # Display stub keys (sec# — master key missing)
  if ((${#stub_fprs[@]} > 0)); then
    warn "Found ${#stub_fprs[@]} key(s) with MISSING master private key (sec#):"
    echo
    for fpr in "${stub_fprs[@]}"; do
      printf "  ${YELLOW}[STUB]${NC}   "
      local uid
      uid=$($GPG --list-keys --with-colons "$fpr" 2> /dev/null \
        | awk -F: '/^uid:/ { print $10; exit }')
      printf "%s\n" "${uid:-<no UID>}"
      printf "           Fingerprint: ${DIM}%s${NC}\n" "$fpr"
    done
    echo
    info "Stub keys still have subkeys and may be functional for signing/encryption."
    info "Only delete them if you're sure you don't need them."
    echo
  fi

  # Ask what to do
  if ((${#orphan_fprs[@]} > 0)); then
    if confirm "Delete all ${#orphan_fprs[@]} ORPHANED public keys (no private key)?"; then
      for fpr in "${orphan_fprs[@]}"; do
        $GPG --batch --yes --delete-keys "$fpr" 2> /dev/null \
          && success "Deleted orphan: ${fpr:0:16}..." \
          || warn "Could not delete ${fpr:0:16}... — may have dependencies."
      done
    fi
    echo
  fi

  if ((${#stub_fprs[@]} > 0)); then
    if confirm "Delete ${#stub_fprs[@]} STUB key(s) (master key missing)?"; then
      warn "This will remove both the public key and any remaining subkey stubs."
      if confirm "Are you sure? This cannot be undone."; then
        for fpr in "${stub_fprs[@]}"; do
          # Must delete secret key stubs first, then public
          $GPG --batch --yes --delete-secret-keys "$fpr" 2> /dev/null || true
          $GPG --batch --yes --delete-keys "$fpr" 2> /dev/null \
            && success "Deleted stub: ${fpr:0:16}..." \
            || warn "Could not fully delete ${fpr:0:16}..."
        done
      fi
    fi
    echo
  fi

  # Also clean up git config if it references a now-deleted key
  local git_signing_key
  git_signing_key=$(git config --global user.signingkey 2> /dev/null || true)
  if [[ -n "$git_signing_key" ]]; then
    # Check if the signing key still exists
    if ! $GPG --list-secret-keys "$git_signing_key" &> /dev/null; then
      warn "Git signing key ${git_signing_key} no longer exists in keyring."
      if confirm "Remove user.signingkey from git config?"; then
        git config --global --unset user.signingkey
        success "Removed stale user.signingkey from git config."
      fi
      if confirm "Disable commit.gpgsign until a new key is configured?"; then
        git config --global commit.gpgsign false
        git config --global tag.gpgsign false
        success "GPG signing disabled in git config."
      fi
    fi
  fi

  success "Cleanup complete."
  echo
  info "Current keyring state:"
  $GPG --list-keys --keyid-format long 2> /dev/null || info "(empty keyring)"
  echo
}

# ──────────────────────────────────────────────────────────────────────────────
# Parse flags
# ──────────────────────────────────────────────────────────────────────────────
DO_CLEANUP=false
DO_SETUP=true

for arg in "$@"; do
  case "$arg" in
    --cleanup)
      DO_CLEANUP=true
      ;;
    --cleanup-only)
      DO_CLEANUP=true
      DO_SETUP=false
      ;;
    --help | -h)
      echo "Usage: $(basename "$0") [--cleanup] [--cleanup-only]"
      echo
      echo "  (no flags)     Set up GPG key for GitHub"
      echo "  --cleanup      Clean orphaned keys, then set up"
      echo "  --cleanup-only Clean orphaned keys only, skip setup"
      exit 0
      ;;
    *)
      fatal "Unknown flag: ${arg}. Use --help for usage."
      ;;
  esac
done

# Run cleanup if requested
if [[ "$DO_CLEANUP" == "true" ]]; then
  run_cleanup
fi

# Exit if cleanup-only
if [[ "$DO_SETUP" == "false" ]]; then
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# Banner
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  GPG Key Setup for GitHub (Commit Signing)${NC}\n"
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
echo

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Choose — new key or existing key
# ──────────────────────────────────────────────────────────────────────────────
printf "${BOLD}${YELLOW}── Step 1: GPG Key ──${NC}\n"
echo

# List existing secret keys
EXISTING_KEYS=()
EXISTING_UIDS=()
EXISTING_TYPES=()

while IFS= read -r line; do
  field1=$(echo "$line" | cut -d: -f1)
  field2=$(echo "$line" | cut -d: -f2)
  field4=$(echo "$line" | cut -d: -f4)
  field10=$(echo "$line" | cut -d: -f10)

  if [[ "$field1" == "sec" ]]; then
    # Skip stubs (no master private key)
    if [[ "$field2" == "#" ]]; then
      current_skip=true
      continue
    fi
    current_skip=false
    current_type="$field4"
  elif [[ "$field1" == "fpr" && "${current_skip:-false}" == "false" ]]; then
    current_fpr="$field10"
  elif [[ "$field1" == "uid" && "${current_skip:-false}" == "false" ]]; then
    EXISTING_KEYS+=("$current_fpr")
    EXISTING_UIDS+=("$field10")
    # Decode key algorithm
    case "$current_type" in
      1) algo="RSA" ;;
      22) algo="EdDSA" ;;
      *) algo="algo:${current_type}" ;;
    esac
    EXISTING_TYPES+=("$algo")
    current_skip=true # Only take first UID per key
  fi
done < <($GPG --list-secret-keys --with-colons --keyid-format long 2> /dev/null)

USE_EXISTING=false

if ((${#EXISTING_KEYS[@]} > 0)); then
  info "Existing GPG secret keys (with valid private key):"
  echo
  for i in "${!EXISTING_KEYS[@]}"; do
    printf "  ${BOLD}[%d]${NC} %s (%s)\n" "$((i + 1))" "${EXISTING_UIDS[$i]}" "${EXISTING_TYPES[$i]}"
    printf "       ${DIM}%s${NC}\n" "${EXISTING_KEYS[$i]}"
  done
  echo
  printf "  ${BOLD}[N]${NC} Generate a new key\n"
  echo

  printf "${BOLD}Choose [1-%d or N]:${NC} " "${#EXISTING_KEYS[@]}"
  read -r CHOICE

  if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
    USE_EXISTING=false
  elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && ((CHOICE >= 1 && CHOICE <= ${#EXISTING_KEYS[@]})); then
    USE_EXISTING=true
    SELECTED_FPR="${EXISTING_KEYS[$((CHOICE - 1))]}"
  else
    fatal "Invalid selection."
  fi
else
  info "No usable GPG secret keys found."
  USE_EXISTING=false
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 1a: Generate new key if needed
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$USE_EXISTING" == "false" ]]; then
  echo
  prompt_input "Full name (for GPG key UID):" GPG_NAME
  prompt_input "Email (must match a verified GitHub email):" GPG_EMAIL

  echo
  info "GPG version: ${GPG_VER_FULL}"

  GPG_BATCH_CONFIG=$(mktemp)

  if ((GPG_MAJOR > 2 || (GPG_MAJOR == 2 && GPG_MINOR >= 3))); then
    info "Using Ed25519 (supported by GPG ${GPG_VER_FULL})."
    # Ed25519 is sign-only. Use cv25519 (ECDH) for encryption subkey.
    cat > "$GPG_BATCH_CONFIG" << EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Subkey-Type: ecdh
Subkey-Curve: cv25519
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: 2y
%commit
EOF
  else
    info "GPG ${GPG_VER_FULL} < 2.3 — using RSA 4096 instead of Ed25519."
    cat > "$GPG_BATCH_CONFIG" << EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: 2y
%commit
EOF
  fi

  echo
  info "Generating GPG key..."
  # Show output — don't swallow errors
  if $GPG --batch --gen-key "$GPG_BATCH_CONFIG"; then
    success "GPG key generated."
  else
    rm -f "$GPG_BATCH_CONFIG"
    fatal "GPG key generation failed. See error above."
  fi
  rm -f "$GPG_BATCH_CONFIG"

  # Find the fingerprint of the key we just created
  SELECTED_FPR=$($GPG --list-secret-keys --with-colons "${GPG_EMAIL}" 2> /dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')

  [[ -n "$SELECTED_FPR" ]] || fatal "Could not find the newly generated key."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Resolve the signing key ID (long format)
# ──────────────────────────────────────────────────────────────────────────────
GPG_SIGNING_KEY=$($GPG --list-secret-keys --keyid-format long --with-colons "$SELECTED_FPR" 2> /dev/null \
  | awk -F: '/^sec:/ { split($5, a, ""); print $5; exit }')
GPG_SIGNING_KEY="${GPG_SIGNING_KEY:-$SELECTED_FPR}"

echo
info "Selected GPG key:"
$GPG --list-secret-keys --keyid-format long "$SELECTED_FPR" 2> /dev/null
echo
info "Fingerprint:  ${SELECTED_FPR}"
info "Signing key:  ${GPG_SIGNING_KEY}"

# Verify the key can actually sign
echo
info "Testing signing capability..."
if echo "test" | $GPG --sign --armor --local-user "$SELECTED_FPR" &> /dev/null; then
  success "Signing test passed."
else
  fatal "Key cannot sign. It may be a stub (missing private key). Run with --cleanup to fix."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Configure git for commit signing
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 2: Git Config ──${NC}\n"
echo

# Get the UID email from the key to suggest for git
KEY_EMAIL=$($GPG --list-keys --with-colons "$SELECTED_FPR" 2> /dev/null \
  | awk -F: '/^uid:/ { print $10; exit }' | sed 's/.*<\(.*\)>.*/\1/')

CURRENT_GIT_EMAIL=$(git config --global user.email 2> /dev/null || true)
CURRENT_GIT_NAME=$(git config --global user.name 2> /dev/null || true)
CURRENT_GIT_SIGKEY=$(git config --global user.signingkey 2> /dev/null || true)

info "Current git config:"
info "  user.name      = ${CURRENT_GIT_NAME:-(not set)}"
info "  user.email     = ${CURRENT_GIT_EMAIL:-(not set)}"
info "  user.signingkey = ${CURRENT_GIT_SIGKEY:-(not set)}"
echo

if confirm "Configure git to use this GPG key for signing?"; then
  # Only set name/email if not already set
  if [[ -z "$CURRENT_GIT_NAME" ]]; then
    local_name=$($GPG --list-keys --with-colons "$SELECTED_FPR" 2> /dev/null \
      | awk -F: '/^uid:/ { print $10; exit }' | sed 's/ <.*//')
    git config --global user.name "$local_name"
    info "Set user.name = ${local_name}"
  fi
  if [[ -z "$CURRENT_GIT_EMAIL" ]]; then
    git config --global user.email "$KEY_EMAIL"
    info "Set user.email = ${KEY_EMAIL}"
  elif [[ "$CURRENT_GIT_EMAIL" != "$KEY_EMAIL" ]]; then
    warn "Git email (${CURRENT_GIT_EMAIL}) differs from GPG key email (${KEY_EMAIL})."
    warn "GitHub requires these to match for 'Verified' badges."
    if confirm "Update git email to ${KEY_EMAIL}?"; then
      git config --global user.email "$KEY_EMAIL"
      info "Updated user.email = ${KEY_EMAIL}"
    fi
  fi

  git config --global user.signingkey "$GPG_SIGNING_KEY"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  git config --global gpg.program "$GPG"

  success "Git config updated for GPG signing."
  echo
  info "  user.signingkey = $(git config --global user.signingkey)"
  info "  commit.gpgsign  = $(git config --global commit.gpgsign)"
  info "  gpg.program     = $(git config --global gpg.program)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Configure GPG agent / TTY
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 3: GPG Agent ──${NC}\n"
echo

mkdir -p "${HOME}/.gnupg"
chmod 700 "${HOME}/.gnupg"

GPG_AGENT_CONF="${HOME}/.gnupg/gpg-agent.conf"
if [[ ! -f "$GPG_AGENT_CONF" ]] || ! grep -q 'default-cache-ttl' "$GPG_AGENT_CONF"; then
  # Detect pinentry
  PINENTRY_BIN=""
  for pe in pinentry-gnome3 pinentry-gtk-2 pinentry-qt pinentry-curses pinentry; do
    if command -v "$pe" &> /dev/null; then
      PINENTRY_BIN=$(command -v "$pe")
      break
    fi
  done

  cat >> "$GPG_AGENT_CONF" << EOF
default-cache-ttl 3600
max-cache-ttl 86400
${PINENTRY_BIN:+pinentry-program ${PINENTRY_BIN}}
EOF
  success "gpg-agent.conf configured (1h cache, pinentry: ${PINENTRY_BIN:-default})."
else
  info "gpg-agent.conf already configured."
fi

# Ensure GPG_TTY is set in shell RC
SHELL_RC="${HOME}/.bashrc"
[[ -n "${ZSH_VERSION:-}" || "$SHELL" == */zsh ]] && SHELL_RC="${HOME}/.zshrc"

if ! grep -q 'GPG_TTY' "$SHELL_RC" 2> /dev/null; then
  echo 'export GPG_TTY=$(tty)' >> "$SHELL_RC"
  success "Added GPG_TTY to ${SHELL_RC}."
fi
GPG_TTY=$(tty)
export GPG_TTY

gpgconf --kill gpg-agent 2> /dev/null || true
gpg-connect-agent /bye 2> /dev/null || true

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Upload GPG key to GitHub
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 4: Upload to GitHub ──${NC}\n"
echo

GPG_PUB_KEY=$($GPG --armor --export "$SELECTED_FPR")
[[ -n "$GPG_PUB_KEY" ]] || fatal "Failed to export public key."

if confirm "Upload this GPG key to GitHub via API?"; then
  prompt_input "GitHub Personal Access Token (scope: admin:gpg_key):" GH_TOKEN true

  HTTP_CODE=$(curl -s -o /tmp/gh_gpg_resp.json -w '%{http_code}' \
    -X POST "https://api.github.com/user/gpg_keys" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$(jq -n --arg key "$GPG_PUB_KEY" '{armored_public_key: $key}')")

  case "$HTTP_CODE" in
    201) success "GPG key uploaded to GitHub." ;;
    422) warn "GPG key already exists on GitHub (duplicate). No action needed." ;;
    401) error "Authentication failed. Check your token and scopes." ;;
    *)
      error "Upload failed (HTTP ${HTTP_CODE})."
      cat /tmp/gh_gpg_resp.json >&2
      ;;
  esac
  rm -f /tmp/gh_gpg_resp.json
else
  echo
  info "Add the key manually at: https://github.com/settings/gpg/new"
  info "Copy the output of: ${GPG} --armor --export ${SELECTED_FPR}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Verify commit signing works
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${YELLOW}── Step 5: Verify ──${NC}\n"
echo

info "Testing commit signing end-to-end..."

TMPDIR_TEST=$(mktemp -d)
cd "$TMPDIR_TEST"
git init -q
git config user.name "Test"
git config user.email "$KEY_EMAIL"
git config user.signingkey "$GPG_SIGNING_KEY"
git config commit.gpgsign true
git config gpg.program "$GPG"

if git commit --allow-empty -m "test signed commit" -q 2> /dev/null; then
  VERIFY_OUTPUT=$(git log --show-signature -1 2>&1)
  if echo "$VERIFY_OUTPUT" | grep -qi "good signature"; then
    success "Signed commit verified successfully!"
  else
    success "Signed commit created (signature verification may need trust)."
  fi
else
  warn "Test commit failed. Check GPG agent / pinentry configuration."
  warn "Try: echo 'test' | ${GPG} --clearsign"
fi

rm -rf "$TMPDIR_TEST"

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────
echo
printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}${GREEN}  GPG setup complete!${NC}\n"
printf "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
echo
info "GPG key:          ${GPG_SIGNING_KEY}"
info "Fingerprint:      ${SELECTED_FPR}"
info "Key expires:      in 2 years (extend with: ${GPG} --edit-key ${SELECTED_FPR} → expire)"
info "Git signing:      $(git config --global commit.gpgsign 2> /dev/null || echo 'not set')"
echo
info "Quick test anytime:"
info "  echo 'test' | ${GPG} --clearsign"
info "  git commit --allow-empty -m 'test signed commit'"
echo
