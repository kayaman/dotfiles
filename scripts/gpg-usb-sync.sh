#!/usr/bin/env bash
# =============================================================================
#  gpg/gpg-usb-sync.sh — Non-destructive GPG keyring backup & restore to USB
#
#  Usage:
#    ./gpg/gpg-usb-sync.sh backup  [--to   local|usb] [--path DIR]
#    ./gpg/gpg-usb-sync.sh restore [--from local|usb] [--path DIR]
#                                  [--snapshot NAME] [--replace]
#    ./gpg/gpg-usb-sync.sh status  [--from local|usb] [--path DIR]
#    ./gpg/gpg-usb-sync.sh help
#
#  Each backup writes a timestamped snapshot dir containing:
#    - gnupg-full.tar.gz.gpg  (full ~/.gnupg, symmetrically encrypted)
#    - public-keys.asc, secret-keys.asc, secret-subkeys.asc
#    - ownertrust.txt, revocs/<fpr>.rev
#    - MANIFEST.txt (sha256 sums + fingerprints + metadata)
#  A `latest` symlink is updated to point at the newest snapshot.
#
#  Companion to gpg-offline-master-key.sh (which is destructive). This script
#  never deletes keys from the local keyring.
# =============================================================================

set -euo pipefail

# ── Colors & helpers ─────────────────────────────────────────
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

confirm() {
  local prompt="${1:-Continue?}"
  printf "${BOLD}%s [y/N]${NC} " "$prompt" >&2
  read -r response
  [[ "$response" =~ ^[Yy]$ ]]
}

confirm_or_die() {
  confirm "$1" || die "Aborted by user."
}

# ── Configuration ────────────────────────────────────────────
GNUPG_HOME="${GNUPGHOME:-$HOME/.gnupg}"
DEFAULT_LOCAL_DIR="$HOME/.dotfiles-backup/gnupg"
USB_SEARCH_PATHS=("/media/$USER" "/mnt" "/run/media/$USER")
USB_SUBDIR="gpg-backup"
SNAPSHOT_PREFIX="gnupg-"
LATEST_LINK="latest"

# ── Dependency detection ─────────────────────────────────────
if command -v gpg2 &> /dev/null; then
  GPG=gpg2
elif command -v gpg &> /dev/null; then
  GPG=gpg
else
  die "Neither gpg2 nor gpg found. Install gnupg first."
fi

check_deps() {
  local missing=() dep
  for dep in tar sha256sum stat df; do
    command -v "$dep" &> /dev/null || missing+=("$dep")
  done
  if ((${#missing[@]} > 0)); then
    die "Missing required tools: ${missing[*]}"
  fi
}

# ── Safety: refuse to write to a /mnt|/media path that's secretly on / ──
verify_not_shadowed_by_mount() {
  local dir="$1"
  local dir_device root_device
  dir_device=$(stat --format='%d' "$dir" 2> /dev/null || stat -f '%d' "$dir" 2> /dev/null)
  root_device=$(stat --format='%d' / 2> /dev/null || stat -f '%d' / 2> /dev/null)

  local actual_source actual_mount
  actual_source=$(df --output=source "$dir" 2> /dev/null | tail -1)
  actual_mount=$(df --output=target "$dir" 2> /dev/null | tail -1)
  info "Backup directory device:  ${actual_source} (mounted on ${actual_mount})"

  case "$dir" in
    /mnt/* | /media/* | /run/media/*)
      if [[ "$dir_device" == "$root_device" ]]; then
        echo
        err "═══════════════════════════════════════════════════════════"
        err "  MOUNT POINT SAFETY CHECK FAILED"
        err "═══════════════════════════════════════════════════════════"
        err "  Path:     ${dir}"
        err "  Lives on: / (root filesystem)"
        err "  Expected: a separate mounted device (e.g. USB drive)"
        err ""
        err "  Mount your encrypted USB drive first, then re-run."
        err "═══════════════════════════════════════════════════════════"
        die "Refusing to write to a /mnt-like path on the root filesystem."
      fi
      ok "Mount point check passed — ${dir} is on a separate device."
      ;;
    /tmp/* | /home/*)
      warn "Backup path is on your local filesystem — NOT secure for production."
      warn "For real use, choose an encrypted USB drive."
      confirm_or_die "Continue anyway (e.g. for testing)?"
      ;;
    *)
      if [[ "$dir_device" == "$root_device" ]]; then
        warn "Backup path ${dir} is on the root filesystem."
        confirm_or_die "Continue writing to root filesystem?"
      fi
      ;;
  esac
}

verify_file_exists_and_nonzero() {
  local filepath="$1"
  local label="$2"
  local min_bytes="${3:-100}"

  [[ -f "$filepath" ]] || die "${label} does not exist at: ${filepath}"

  local actual_size
  actual_size=$(stat --format='%s' "$filepath" 2> /dev/null || stat -f '%z' "$filepath" 2> /dev/null)

  if [[ -z "$actual_size" ]] || ((actual_size < min_bytes)); then
    die "${label} is suspiciously small (${actual_size:-0} bytes, expected ≥${min_bytes}). Backup may be corrupt."
  fi
  ok "${label} verified (${actual_size} bytes)"
}

# ── USB / path resolution ────────────────────────────────────
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

resolve_destination() {
  local media="$1"
  local custom_path="${2:-}"

  if [[ -n "$custom_path" ]]; then
    echo "$custom_path"
    return
  fi

  case "$media" in
    local) echo "$DEFAULT_LOCAL_DIR" ;;
    usb)
      local usb_path
      usb_path="$(detect_usb)" || die "No USB drive detected. Use --path to specify mount point."
      info "Detected USB: $usb_path" >&2
      echo "$usb_path/$USB_SUBDIR"
      ;;
    *) die "Unknown media type: $media (use: local, usb)" ;;
  esac
}

# ── Backup ───────────────────────────────────────────────────
cmd_backup() {
  local media="usb"
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
      -h | --help)
        usage
        return 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  section "Backup ~/.gnupg → ${media}"

  [[ -d "$GNUPG_HOME" ]] || die "GNUPGHOME not found: $GNUPG_HOME"

  local dest
  dest="$(resolve_destination "$media" "$custom_path")"
  mkdir -p "$dest"
  verify_not_shadowed_by_mount "$dest"

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local snap="$dest/${SNAPSHOT_PREFIX}${ts}"
  mkdir -p "$snap" "$snap/revocs"
  chmod 700 "$snap"

  info "Snapshot dir : $snap"
  info "GNUPGHOME    : $GNUPG_HOME"

  # 1. Encrypted tarball of the full ~/.gnupg
  local tarball="$snap/gnupg-full.tar.gz.gpg"
  info "Creating encrypted tarball (you will be prompted for a passphrase)..."
  tar czf - -C "$(dirname "$GNUPG_HOME")" "$(basename "$GNUPG_HOME")" \
    | $GPG --symmetric --cipher-algo AES256 --output "$tarball" \
    || die "Failed to create encrypted tarball."
  chmod 600 "$tarball"
  verify_file_exists_and_nonzero "$tarball" "Encrypted tarball" 500

  # 2. Armored exports
  local pub="$snap/public-keys.asc"
  local sec="$snap/secret-keys.asc"
  local subs="$snap/secret-subkeys.asc"
  local trust="$snap/ownertrust.txt"

  info "Exporting public keys..."
  $GPG --armor --export > "$pub" 2> /dev/null || true
  info "Exporting secret keys..."
  $GPG --armor --export-secret-keys > "$sec" 2> /dev/null || true
  info "Exporting secret subkeys..."
  $GPG --armor --export-secret-subkeys > "$subs" 2> /dev/null || true
  info "Exporting ownertrust..."
  $GPG --export-ownertrust > "$trust" 2> /dev/null || true
  chmod 600 "$pub" "$sec" "$subs" "$trust"

  # Tolerate empty exports (e.g. no secret keys yet) but warn
  [[ -s "$pub" ]] || warn "No public keys exported — keyring may be empty."
  [[ -s "$sec" ]] || warn "No secret keys exported."

  # 3. Revocation certificates
  if [[ -d "$GNUPG_HOME/openpgp-revocs.d" ]]; then
    local copied=0
    for rev in "$GNUPG_HOME/openpgp-revocs.d/"*.rev; do
      [[ -f "$rev" ]] || continue
      cp "$rev" "$snap/revocs/"
      chmod 600 "$snap/revocs/$(basename "$rev")"
      copied=$((copied + 1))
    done
    info "Copied $copied revocation certificate(s)."
  fi

  # 4. Collect fingerprints for the manifest
  local fprs
  fprs=$($GPG --list-keys --with-colons 2> /dev/null \
    | awk -F: '/^fpr:/ { print $10 }' | sort -u)

  # 5. Manifest with sha256 sums
  section "Writing manifest"
  local manifest="$snap/MANIFEST.txt"
  {
    echo "# GPG USB backup manifest"
    echo "host:        $(hostname)"
    echo "user:        $USER"
    echo "date:        $(date -Iseconds)"
    echo "gpg:         $($GPG --version | head -1)"
    echo "gnupghome:   $GNUPG_HOME"
    echo
    echo "# Fingerprints (public keyring):"
    if [[ -n "$fprs" ]]; then
      while read -r f; do echo "fpr: $f"; done <<< "$fprs"
    else
      echo "fpr: (none)"
    fi
    echo
    echo "# SHA-256 of snapshot files (relative to snapshot dir):"
    (
      cd "$snap"
      find . -type f ! -name MANIFEST.txt -print0 \
        | sort -z \
        | xargs -0 sha256sum
    )
  } > "$manifest"
  chmod 600 "$manifest"
  ok "Manifest: $manifest"

  # 6. Update `latest` symlink
  ln -sfn "$(basename "$snap")" "$dest/$LATEST_LINK"
  ok "Updated symlink: $dest/$LATEST_LINK → $(basename "$snap")"

  # 7. Tarball integrity (decrypt-list round trip)
  section "Post-write verification"
  info "Tarball listing test (requires the passphrase again)..."
  if $GPG --decrypt "$tarball" 2> /dev/null | tar tzf - > /dev/null; then
    ok "Tarball decrypts and lists cleanly."
  else
    warn "Could not verify tarball end-to-end (passphrase skipped?). The file is on disk regardless."
  fi

  echo
  ok "Backup complete."
  info "Snapshot: $snap"
  info "Files:"
  ls -lh "$snap" | awk 'NR>1 {printf "       %s  %s\n", $5, $NF}'
  echo
  warn "Safely eject/unmount the media before unplugging."
}

# ── Restore ──────────────────────────────────────────────────
cmd_restore() {
  local media="usb"
  local custom_path=""
  local snapshot=""
  local replace=0

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
      --snapshot)
        snapshot="$2"
        shift 2
        ;;
      --replace)
        replace=1
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  section "Restore GPG keyring from ${media}"

  local src
  src="$(resolve_destination "$media" "$custom_path")"
  [[ -d "$src" ]] || die "Source directory not found: $src"

  # Pick snapshot
  local snap
  if [[ -n "$snapshot" ]]; then
    snap="$src/$snapshot"
  elif [[ -L "$src/$LATEST_LINK" ]]; then
    snap="$src/$(readlink "$src/$LATEST_LINK")"
  else
    snap=$(find "$src" -maxdepth 1 -type d -name "${SNAPSHOT_PREFIX}*" \
      | sort | tail -1)
  fi
  [[ -n "$snap" && -d "$snap" ]] || die "No snapshot found in $src (use --snapshot NAME)."
  info "Snapshot: $snap"

  # Verify manifest
  local manifest="$snap/MANIFEST.txt"
  [[ -f "$manifest" ]] || die "Manifest missing: $manifest"

  section "Verifying manifest checksums"
  local sums
  sums=$(awk '/^[a-f0-9]{64}  / { print }' "$manifest")
  if [[ -z "$sums" ]]; then
    die "Manifest contains no checksums."
  fi
  (cd "$snap" && echo "$sums" | sha256sum --check --quiet) \
    || die "Checksum verification failed — snapshot is corrupt."
  ok "All snapshot files match manifest checksums."

  # Decrypt tarball into a temp dir
  local tarball="$snap/gnupg-full.tar.gz.gpg"
  [[ -f "$tarball" ]] || die "Encrypted tarball missing: $tarball"

  local workdir
  workdir=$(mktemp -d -t gpg-usb-sync.XXXXXX)
  # Expand $workdir at trap-definition time, not on EXIT — $workdir is `local`
  # and would be unbound when the trap fires after this function returns
  # (set -u then aborts the cleanup with "workdir: unbound variable").
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  info "Decrypting tarball (you will be prompted for the passphrase)..."
  $GPG --decrypt "$tarball" 2> /dev/null | tar xzf - -C "$workdir" \
    || die "Failed to decrypt or extract tarball."
  local extracted_home
  extracted_home="$workdir/$(basename "$GNUPG_HOME")"
  [[ -d "$extracted_home" ]] || die "Extracted tarball missing expected $(basename "$GNUPG_HOME") dir."
  ok "Tarball extracted to: $extracted_home"

  if [[ ! -d "$GNUPG_HOME" ]]; then
    # Fresh install: drop the extracted GNUPGHOME in place
    info "No existing $GNUPG_HOME — installing snapshot as-is."
    mkdir -p "$(dirname "$GNUPG_HOME")"
    mv "$extracted_home" "$GNUPG_HOME"
    chmod 700 "$GNUPG_HOME"
    ok "Restored full keyring to $GNUPG_HOME"
  elif ((replace)); then
    warn "Existing $GNUPG_HOME will be replaced."
    confirm_or_die "Move existing $GNUPG_HOME aside and replace it?"
    local backup_path
    backup_path="${GNUPG_HOME}.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$GNUPG_HOME" "$backup_path"
    ok "Previous keyring archived: $backup_path"
    mv "$extracted_home" "$GNUPG_HOME"
    chmod 700 "$GNUPG_HOME"
    ok "Restored full keyring to $GNUPG_HOME"
  else
    # Merge mode: import armored files; never destroy existing keys
    info "Merging snapshot into existing $GNUPG_HOME (use --replace for full overwrite)."
    [[ -s "$snap/public-keys.asc" ]] && $GPG --import "$snap/public-keys.asc" 2>&1 | sed 's/^/       /'
    [[ -s "$snap/secret-keys.asc" ]] && $GPG --import "$snap/secret-keys.asc" 2>&1 | sed 's/^/       /'
    [[ -s "$snap/ownertrust.txt" ]] && $GPG --import-ownertrust < "$snap/ownertrust.txt" 2>&1 | sed 's/^/       /'

    # Copy missing revocation certs only
    if [[ -d "$snap/revocs" ]]; then
      mkdir -p "$GNUPG_HOME/openpgp-revocs.d"
      chmod 700 "$GNUPG_HOME/openpgp-revocs.d"
      for rev in "$snap/revocs/"*.rev; do
        [[ -f "$rev" ]] || continue
        local target
        target="$GNUPG_HOME/openpgp-revocs.d/$(basename "$rev")"
        if [[ ! -e "$target" ]]; then
          cp "$rev" "$target"
          chmod 600 "$target"
          info "Restored revocation cert: $(basename "$rev")"
        fi
      done
    fi
    ok "Merge import complete."
  fi

  section "Post-restore keyring"
  $GPG --list-secret-keys --keyid-format long 2> /dev/null || true
  echo
  ok "Restore complete."
}

# ── Status ───────────────────────────────────────────────────
cmd_status() {
  local media="usb"
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
      -h | --help)
        usage
        return 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  section "GPG USB sync status"

  if [[ -d "$GNUPG_HOME" ]]; then
    local pubcount seccount
    pubcount=$($GPG --list-keys --with-colons 2> /dev/null | grep -c '^pub:' || true)
    seccount=$($GPG --list-secret-keys --with-colons 2> /dev/null | grep -c '^sec:' || true)
    ok "GNUPGHOME: $GNUPG_HOME ($pubcount public, $seccount secret)"
  else
    warn "GNUPGHOME: not found ($GNUPG_HOME)"
  fi

  local src
  if src=$(resolve_destination "$media" "$custom_path" 2> /dev/null); then
    info "Source   : $src"
    if [[ -d "$src" ]]; then
      local snaps
      snaps=$(find "$src" -maxdepth 1 -type d -name "${SNAPSHOT_PREFIX}*" | sort)
      if [[ -z "$snaps" ]]; then
        warn "No snapshots found in $src"
      else
        echo
        info "Snapshots:"
        while read -r s; do
          local size
          size=$(du -sh "$s" 2> /dev/null | cut -f1)
          echo "       $size  $(basename "$s")"
        done <<< "$snaps"
        if [[ -L "$src/$LATEST_LINK" ]]; then
          echo
          ok "latest → $(readlink "$src/$LATEST_LINK")"
        fi
      fi
    else
      warn "Source directory does not exist."
    fi
  else
    warn "Cannot resolve source for media=$media (USB not mounted?)"
  fi
}

# ── Main ─────────────────────────────────────────────────────
usage() {
  cat << 'EOF'
Usage: gpg/gpg-usb-sync.sh <command> [options]

Commands:
  backup    Snapshot ~/.gnupg to a destination
  restore   Restore ~/.gnupg from a snapshot
  status    Show local keyring and snapshots on destination
  help      Show this help

Options:
  --to     <local|usb>      Destination for backup (default: usb)
  --from   <local|usb>      Source for restore/status (default: usb)
  --path   <dir>            Custom path (overrides auto-detection)
  --snapshot <name>         Specific snapshot dir name (restore only)
  --replace                 Replace ~/.gnupg with the snapshot (restore only).
                            Default behavior is import-merge.

Examples:
  # Snapshot ~/.gnupg to a mounted USB drive
  ./gpg/gpg-usb-sync.sh backup --to usb

  # Snapshot to a custom path (e.g. for testing)
  ./gpg/gpg-usb-sync.sh backup --to local --path /tmp/gpg-usb-test

  # Restore the latest snapshot, merging into existing ~/.gnupg
  ./gpg/gpg-usb-sync.sh restore --from usb

  # Pick a specific snapshot and replace the existing keyring
  ./gpg/gpg-usb-sync.sh restore --from usb --snapshot gnupg-20260515-101530 --replace

  # See what's on the USB
  ./gpg/gpg-usb-sync.sh status --from usb
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
    backup) cmd_backup "$@" ;;
    restore) cmd_restore "$@" ;;
    status) cmd_status "$@" ;;
    help | -h | --help) usage ;;
    *) die "Unknown command: $cmd (try: help)" ;;
  esac
}

main "$@"
