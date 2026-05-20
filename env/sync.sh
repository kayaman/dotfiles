#!/usr/bin/env bash
# =============================================================================
#  env/sync.sh — Encrypt & sync ~/.env using SOPS + age
#
#  Usage:
#    ./env/sync.sh encrypt [--to local|usb|phone] [--path /custom/path]
#    ./env/sync.sh decrypt [--from local|usb|phone] [--path /custom/path]
#    ./env/sync.sh keygen                 # Generate a new age key pair
#    ./env/sync.sh status                 # Show current key & backup info
#
#  The encrypted file is named .env.enc and can be stored on:
#    local  — a local directory (default: ~/.dotfiles-backup)
#    usb    — a mounted USB drive (auto-detected or --path)
#    phone  — an Android phone via MTP (auto-detected or --path)
# =============================================================================

set -euo pipefail

# ── Colors & helpers ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err() { echo -e "${RED}[ERR]${NC}   $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${NC}"; }

die() {
  err "$*"
  exit 1
}

# ── Configuration ─────────────────────────────────────────────
ENV_FILE="$HOME/.env"
ENC_FILENAME=".env.enc"
AGE_KEY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age"
AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"
DEFAULT_LOCAL_DIR="$HOME/.dotfiles-backup"
USB_SEARCH_PATHS=("/media/$USER" "/mnt" "/run/media/$USER")
MTP_SEARCH_PATHS=("/run/user/$(id -u)/gvfs" "/media/$USER")
PHONE_SUBDIR="dotfiles-backup"

# ── Dependency checks ────────────────────────────────────────
check_deps() {
  local missing=()
  for cmd in sops age age-keygen; do
    command -v "$cmd" &> /dev/null || missing+=("$cmd")
  done
  if ((${#missing[@]} > 0)); then
    err "Missing required tools: ${missing[*]}"
    echo ""
    info "Install them with:"
    info "  age/age-keygen : https://github.com/FiloSottile/age#installation"
    info "                   openSUSE: sudo zypper install age"
    info "                   Ubuntu:   sudo apt install age"
    info "  sops           : https://github.com/getsops/sops/releases"
    info "                   or: go install github.com/getsops/sops/v3/cmd/sops@latest"
    exit 1
  fi
}

# ── Age key management ───────────────────────────────────────
get_age_public_key() {
  if [[ ! -f "$AGE_KEY_FILE" ]]; then
    return 1
  fi
  grep -o 'age1[a-z0-9]*' "$AGE_KEY_FILE" | head -1
}

cmd_keygen() {
  section "Age Key Generation"

  if [[ -f "$AGE_KEY_FILE" ]]; then
    warn "Age key already exists at: $AGE_KEY_FILE"
    local pubkey
    pubkey="$(get_age_public_key)"
    info "Public key: $pubkey"
    read -rp "Overwrite? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || {
      info "Aborted."
      return
    }
  fi

  mkdir -p "$AGE_KEY_DIR"
  age-keygen -o "$AGE_KEY_FILE" 2>&1
  chmod 600 "$AGE_KEY_FILE"

  local pubkey
  pubkey="$(get_age_public_key)"
  ok "Age key pair generated"
  info "Key file : $AGE_KEY_FILE"
  info "Public key: $pubkey"
  echo ""
  warn "Back up $AGE_KEY_FILE securely — you need it to decrypt your .env"
}

# ── Media detection ──────────────────────────────────────────
detect_usb() {
  for base in "${USB_SEARCH_PATHS[@]}"; do
    if [[ -d "$base" ]]; then
      for mount in "$base"/*/; do
        if mountpoint -q "${mount%/}" 2> /dev/null; then
          echo "${mount%/}"
          return 0
        fi
      done
    fi
  done
  return 1
}

detect_phone() {
  for base in "${MTP_SEARCH_PATHS[@]}"; do
    if [[ -d "$base" ]]; then
      # Look for MTP/gvfs-mounted phone directories
      for mount in "$base"/mtp-*/ "$base"/*/; do
        if [[ -d "${mount%/}" ]]; then
          # Try common internal storage paths
          for storage in "${mount%/}/Internal shared storage" \
            "${mount%/}/Internal storage" \
            "${mount%/}/Phone" \
            "${mount%/}"; do
            if [[ -d "$storage" ]]; then
              echo "$storage"
              return 0
            fi
          done
        fi
      done
    fi
  done
  return 1
}

resolve_destination() {
  local media="$1"
  local custom_path="${2:-}"

  if [[ -n "$custom_path" ]]; then
    echo "$custom_path"
    return
  fi

  case "$media" in
    local)
      echo "$DEFAULT_LOCAL_DIR"
      ;;
    usb)
      local usb_path
      usb_path="$(detect_usb)" || die "No USB drive detected. Use --path to specify mount point."
      info "Detected USB: $usb_path"
      echo "$usb_path/$PHONE_SUBDIR"
      ;;
    phone)
      local phone_path
      phone_path="$(detect_phone)" || die "No phone detected via MTP. Mount your phone first or use --path."
      info "Detected phone: $phone_path"
      echo "$phone_path/$PHONE_SUBDIR"
      ;;
    *)
      die "Unknown media type: $media (use: local, usb, phone)"
      ;;
  esac
}

# ── Encrypt ──────────────────────────────────────────────────
cmd_encrypt() {
  local media="local"
  local custom_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)
        media="$2"
        shift 2
        ;;
      --path)
        custom_path="$2"
        shift 2
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  section "Encrypt ~/.env"

  [[ -f "$ENV_FILE" ]] || die "Source file not found: $ENV_FILE"

  local pubkey
  pubkey="$(get_age_public_key)" || die "No age key found. Run: $0 keygen"

  local dest
  dest="$(resolve_destination "$media" "$custom_path")"
  mkdir -p "$dest"

  local enc_file="$dest/$ENC_FILENAME"

  info "Source    : $ENV_FILE"
  info "Dest      : $enc_file"
  info "Recipient : $pubkey"
  info "Media     : $media"

  # Encrypt with SOPS using age — treat .env as dotenv format
  sops encrypt \
    --age "$pubkey" \
    --input-type dotenv \
    --output-type dotenv \
    "$ENV_FILE" > "$enc_file"

  chmod 600 "$enc_file"
  ok "Encrypted and saved to: $enc_file"

  # Also back up the age key alongside (optional, prompted)
  local key_backup="$dest/.age-key.txt"
  if [[ ! -f "$key_backup" ]]; then
    echo ""
    warn "Your age private key is needed to decrypt. Back it up too?"
    read -rp "Copy age key to $dest? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      cp "$AGE_KEY_FILE" "$key_backup"
      chmod 600 "$key_backup"
      ok "Age key backed up to: $key_backup"
    fi
  fi
}

# ── Decrypt ──────────────────────────────────────────────────
cmd_decrypt() {
  local media="local"
  local custom_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from)
        media="$2"
        shift 2
        ;;
      --path)
        custom_path="$2"
        shift 2
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  section "Decrypt .env → ~/"

  local src
  src="$(resolve_destination "$media" "$custom_path")"
  local enc_file="$src/$ENC_FILENAME"

  [[ -f "$enc_file" ]] || die "Encrypted file not found: $enc_file"

  # Check for age key — offer to restore from backup if missing
  if [[ ! -f "$AGE_KEY_FILE" ]]; then
    warn "Age key not found at: $AGE_KEY_FILE"
    local key_backup="$src/.age-key.txt"
    if [[ -f "$key_backup" ]]; then
      info "Found backed-up key at: $key_backup"
      read -rp "Restore age key from backup? (Y/n): " confirm
      if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        mkdir -p "$AGE_KEY_DIR"
        cp "$key_backup" "$AGE_KEY_FILE"
        chmod 600 "$AGE_KEY_FILE"
        ok "Age key restored to: $AGE_KEY_FILE"
      else
        die "Cannot decrypt without age key."
      fi
    else
      die "No age key found. Place your key at $AGE_KEY_FILE or use: $0 keygen"
    fi
  fi

  # Warn if ~/.env already exists
  if [[ -f "$ENV_FILE" ]]; then
    warn "$ENV_FILE already exists"
    read -rp "Overwrite? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || {
      info "Aborted."
      return
    }
  fi

  info "Source: $enc_file"
  info "Dest  : $ENV_FILE"

  # Decrypt with SOPS — age key is auto-discovered from keys.txt
  sops decrypt \
    --input-type dotenv \
    --output-type dotenv \
    "$enc_file" > "$ENV_FILE"

  chmod 600 "$ENV_FILE"
  ok "Decrypted and installed: $ENV_FILE"
}

# ── Status ───────────────────────────────────────────────────
cmd_status() {
  section "Environment Sync Status"

  # Age key
  if [[ -f "$AGE_KEY_FILE" ]]; then
    local pubkey
    pubkey="$(get_age_public_key)"
    ok "Age key  : $AGE_KEY_FILE"
    info "Public key: $pubkey"
  else
    warn "Age key  : not found (run: $0 keygen)"
  fi

  # Source .env
  if [[ -f "$ENV_FILE" ]]; then
    local count
    count="$(grep -c '=' "$ENV_FILE" 2> /dev/null || echo 0)"
    ok "$ENV_FILE : exists ($count variables)"
  else
    warn "$ENV_FILE : not found"
  fi

  echo ""
  info "Backup locations:"

  # Local
  if [[ -f "$DEFAULT_LOCAL_DIR/$ENC_FILENAME" ]]; then
    ok "  local : $DEFAULT_LOCAL_DIR/$ENC_FILENAME ($(stat -c%y "$DEFAULT_LOCAL_DIR/$ENC_FILENAME" 2> /dev/null | cut -d. -f1))"
  else
    warn "  local : no backup"
  fi

  # USB
  local usb_path
  if usb_path="$(detect_usb 2> /dev/null)"; then
    if [[ -f "$usb_path/$PHONE_SUBDIR/$ENC_FILENAME" ]]; then
      ok "  usb   : $usb_path/$PHONE_SUBDIR/$ENC_FILENAME"
    else
      warn "  usb   : drive mounted at $usb_path but no backup found"
    fi
  else
    info "  usb   : no drive detected"
  fi

  # Phone
  local phone_path
  if phone_path="$(detect_phone 2> /dev/null)"; then
    if [[ -f "$phone_path/$PHONE_SUBDIR/$ENC_FILENAME" ]]; then
      ok "  phone : $phone_path/$PHONE_SUBDIR/$ENC_FILENAME"
    else
      warn "  phone : mounted at $phone_path but no backup found"
    fi
  else
    info "  phone : not connected"
  fi
}

# ── Main ─────────────────────────────────────────────────────
usage() {
  cat << 'EOF'
Usage: env/sync.sh <command> [options]

Commands:
  encrypt   Encrypt ~/.env and save to a destination
  decrypt   Decrypt .env.enc from a source and install to ~/
  keygen    Generate a new age key pair for SOPS encryption
  status    Show age key, ~/.env, and backup status

Options:
  --to   <local|usb|phone>   Destination media for encrypt (default: local)
  --from <local|usb|phone>   Source media for decrypt (default: local)
  --path <dir>               Custom path (overrides auto-detection)

Examples:
  # First-time setup: generate age keys
  ./env/sync.sh keygen

  # Encrypt ~/.env to local backup
  ./env/sync.sh encrypt

  # Encrypt ~/.env to USB drive
  ./env/sync.sh encrypt --to usb

  # Encrypt ~/.env to phone (MTP)
  ./env/sync.sh encrypt --to phone

  # Encrypt to a specific path
  ./env/sync.sh encrypt --to local --path /tmp/my-backup

  # On a new machine: decrypt from USB
  ./env/sync.sh decrypt --from usb

  # Check status
  ./env/sync.sh status
EOF
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local cmd="$1"
  shift

  check_deps

  case "$cmd" in
    encrypt) cmd_encrypt "$@" ;;
    decrypt) cmd_decrypt "$@" ;;
    keygen) cmd_keygen ;;
    status) cmd_status ;;
    help | -h | --help) usage ;;
    *) die "Unknown command: $cmd (try: help)" ;;
  esac
}

main "$@"
