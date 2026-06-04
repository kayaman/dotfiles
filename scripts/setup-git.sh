#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${RED}[WARN]${NC}  $*"; }
prompt() { echo -e -n "${BOLD}$*${NC} "; }

echo -e "\n${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Git User & GPG Signing Setup         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}\n"

# ── 0. Load Defaults from dotfiles.toml ────────────────────────
config_file="$(dirname "$0")/../dotfiles.toml"
sops_file="$(dirname "$0")/../dotfiles.sops.toml"

toml_name=""
toml_email=""
toml_signingkey=""

if [[ -f "$sops_file" ]] && command -v sops &> /dev/null; then
  info "Reading defaults from dotfiles.sops.toml..."
  content=$(sops -d "$sops_file" 2> /dev/null)
elif [[ -f "$config_file" ]]; then
  info "Reading defaults from dotfiles.toml..."
  content=$(cat "$config_file" 2> /dev/null)
fi

if [[ -n "${content:-}" ]]; then
  # Parse git section. Python emits NUL-delimited key=value records and bash
  # reads them directly — no eval, so a config value containing quotes, $(),
  # or backticks can never be executed as shell.
  while IFS= read -r -d '' _tkv; do
    case "${_tkv%%=*}" in
      name) toml_name=${_tkv#*=} ;;
      email) toml_email=${_tkv#*=} ;;
      signingkey) toml_signingkey=${_tkv#*=} ;;
    esac
  done < <(printf '%s' "$content" | python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import toml as tomllib
    except ImportError:
        sys.exit(0)

try:
    data = tomllib.loads(sys.stdin.read())
    git = data.get('git', {})
    for k, v in git.items():
        if isinstance(v, str):
            sys.stdout.write(f'{k}={v}\0')
except Exception:
    pass
" 2> /dev/null)
fi

# ── 1. User Name ──────────────────────────────────────────────
current_name=$(git config --global user.name || echo "$toml_name")
prompt "Enter Git user.name [${current_name}]:"
read -r new_name
if [[ -n "$new_name" ]]; then
  git config --global user.name "$new_name"
  ok "Set user.name to '$new_name'"
elif [[ -n "$current_name" ]]; then
  git config --global user.name "$current_name"
  ok "Set user.name to '$current_name'"
else
  warn "user.name is required!"
  exit 1
fi

# ── 2. User Email ─────────────────────────────────────────────
current_email=$(git config --global user.email || echo "$toml_email")
prompt "Enter Git user.email [${current_email}]:"
read -r new_email
if [[ -n "$new_email" ]]; then
  git config --global user.email "$new_email"
  ok "Set user.email to '$new_email'"
elif [[ -n "$current_email" ]]; then
  git config --global user.email "$current_email"
  ok "Set user.email to '$current_email'"
else
  warn "user.email is required!"
  exit 1
fi

# ── 3. GPG Signing ────────────────────────────────────────────
echo ""
prompt "Do you want to configure GPG commit signing? [y/N]:"
read -r setup_gpg
if [[ "${setup_gpg,,}" =~ ^(y|yes)$ ]]; then
  if ! command -v gpg &> /dev/null && ! command -v gpg2 &> /dev/null; then
    warn "GPG is not installed. Please install it first."
  else
    echo ""
    info "Available GPG secret keys:"
    gpg --list-secret-keys --keyid-format=long | grep -E '(sec|uid)' || echo "No secret keys found."

    echo ""
    current_signingkey=$(git config --global user.signingkey || echo "$toml_signingkey")
    prompt "Enter the GPG Key ID to use (the part after rsa4096/ or ed25519/) [${current_signingkey}]:"
    read -r new_keyid

    if [[ -n "$new_keyid" ]]; then
      git config --global user.signingkey "$new_keyid"
      git config --global commit.gpgsign true
      git config --global tag.gpgSign true
      ok "Set user.signingkey to '$new_keyid' and enabled signing."
    elif [[ -n "$current_signingkey" ]]; then
      git config --global user.signingkey "$current_signingkey"
      git config --global commit.gpgsign true
      git config --global tag.gpgSign true
      ok "Set user.signingkey to '$current_signingkey' and enabled signing."
    else
      warn "No key selected, GPG setup skipped."
    fi
  fi
else
  info "Configuration skipped."
fi

echo -e "\n${GREEN}Git setup complete!${NC}\n"
git config --global -l | grep -E '^user\.|^commit\.gpgsign|^tag\.gpgsign'
