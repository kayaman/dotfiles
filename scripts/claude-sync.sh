#!/usr/bin/env bash
#
# claude-sync.sh — back up / restore the curated parts of ~/.claude
#
#   claude-sync.sh backup              ~/.claude  ->  repo claude/
#   claude-sync.sh restore [--no-plugins]   repo claude/  ->  ~/.claude
#
# Only a small, portable, non-secret set is synced: settings.json, hooks/,
# and skills/. Auth tokens (.credentials.json), machine/account state
# (~/.claude.json) and all transient caches/sessions are deliberately skipped.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${RED}[WARN]${NC}  $*"; }
err() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HOME/.claude"
STORE="$REPO/claude"

# Curated allowlist — the only paths (relative to ~/.claude) ever synced.
ITEMS=(settings.json hooks skills)

usage() {
  cat << EOF
Usage: claude-sync.sh <command> [options]

Commands:
  backup              Copy curated ~/.claude config into the repo (claude/).
  restore             Copy repo config into ~/.claude and reinstall plugins.

Options (restore):
  --no-plugins        Restore files only; skip plugin/marketplace reinstall.
  -h, --help          Show this help.

Synced: ${ITEMS[*]}
Never synced: .credentials.json (auth), ~/.claude.json, caches/sessions.
EOF
}

# Abort if a credentials file ever slipped into a synced location.
assert_no_secrets() {
  local root="$1"
  if find "$root" -name '*.credentials*' -o -name '.credentials.json' \
    | grep -q .; then
    err "Refusing to proceed: credential file found under $root"
    exit 1
  fi
}

do_backup() {
  [[ -d "$SRC" ]] || {
    err "No ~/.claude directory found"
    exit 1
  }

  mkdir -p "$STORE"
  local copied=()
  for item in "${ITEMS[@]}"; do
    local from="$SRC/$item"
    [[ -e "$from" ]] || continue
    rm -rf "${STORE:?}/$item"
    cp -a "$from" "$STORE/$item"
    copied+=("$item")
  done

  assert_no_secrets "$STORE"

  if [[ ${#copied[@]} -eq 0 ]]; then
    warn "Nothing to back up (no curated files present in ~/.claude)"
  else
    ok "Backed up to $STORE: ${copied[*]}"
  fi
}

# Reinstall marketplaces and enabled plugins from settings.json. Best-effort:
# individual failures (offline, not logged in) warn but never abort.
restore_plugins() {
  local settings="$STORE/settings.json"
  [[ -f "$settings" ]] || return 0

  if ! command -v claude &> /dev/null; then
    warn "claude CLI not found — skipping plugin reinstall"
    return 0
  fi
  if ! command -v jq &> /dev/null; then
    warn "jq not found — skipping plugin reinstall"
    return 0
  fi

  info "Adding extra marketplaces…"
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    claude plugin marketplace add "$repo" \
      && ok "marketplace: $repo" \
      || warn "marketplace add failed (may already exist): $repo"
  done < <(jq -r '.extraKnownMarketplaces // {}
                  | to_entries[]
                  | select(.value.source.source == "github")
                  | .value.source.repo' "$settings")

  info "Installing enabled plugins…"
  while IFS= read -r plugin; do
    [[ -n "$plugin" ]] || continue
    claude plugin install "$plugin" \
      && ok "plugin: $plugin" \
      || warn "plugin install failed (offline / not logged in?): $plugin"
  done < <(jq -r '.enabledPlugins // {}
                  | to_entries[]
                  | select(.value == true)
                  | .key' "$settings")
}

do_restore() {
  local with_plugins=1
  for arg in "$@"; do
    case "$arg" in
      --no-plugins) with_plugins=0 ;;
      *)
        err "Unknown option: $arg"
        usage
        exit 1
        ;;
    esac
  done

  [[ -d "$STORE" ]] || {
    err "No stored config at $STORE — run a backup first"
    exit 1
  }
  assert_no_secrets "$STORE"
  mkdir -p "$SRC"

  # Snapshot anything we are about to overwrite.
  local backup_dir
  backup_dir="$SRC/backups/restore-$(date +%Y-%m-%d-%H%M%S)"
  local restored=()
  for item in "${ITEMS[@]}"; do
    local from="$STORE/$item"
    [[ -e "$from" ]] || continue
    if [[ -e "$SRC/$item" ]]; then
      mkdir -p "$backup_dir"
      cp -a "$SRC/$item" "$backup_dir/"
    fi
    rm -rf "${SRC:?}/$item"
    cp -a "$from" "$SRC/$item"
    restored+=("$item")
  done

  [[ -d "$SRC/hooks" ]] && chmod +x "$SRC"/hooks/*.sh 2> /dev/null || true

  if [[ ${#restored[@]} -eq 0 ]]; then
    warn "Nothing to restore"
  else
    ok "Restored to ~/.claude: ${restored[*]}"
    [[ -d "$backup_dir" ]] && info "Previous files saved to $backup_dir"
  fi

  if [[ "$with_plugins" -eq 1 ]]; then
    restore_plugins
  else
    info "Skipping plugin reinstall (--no-plugins)"
  fi

  info "Login is not synced — run 'claude' to authenticate on this machine."
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    backup) do_backup ;;
    restore) do_restore "$@" ;;
    -h | --help | help | "") usage ;;
    *)
      err "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
