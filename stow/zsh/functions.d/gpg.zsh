#!/usr/bin/env zsh
# GPG helpers + GitHub PAT clipboard shortcuts.

gpg-by-id() {
  gpg --armor --export-options export-minimal --export "$1" | xclip -sel clip
  echo "The GPG public key was copied to clipboard"
}

# Set up GPG signing for git commits and tags.
# Usage:
#   setup-gpg-signing            # auto-detect or pick from available keys
#   setup-gpg-signing <KEY_ID>   # use a specific key ID
#   setup-gpg-signing --off      # disable GPG signing
setup-gpg-signing() {
  local gpg_bin
  if command -v gpg2 &> /dev/null; then
    gpg_bin=gpg2
  elif command -v gpg &> /dev/null; then
    gpg_bin=gpg
  else
    echo "Error: gpg not found. Install gnupg first." >&2
    return 1
  fi

  # --off: disable signing
  if [[ "${1:-}" == "--off" ]]; then
    git config --global --unset user.signingkey 2> /dev/null || true
    git config --global commit.gpgsign false
    git config --global tag.gpgSign false
    echo "GPG commit/tag signing disabled."
    return 0
  fi

  local key_id="${1:-}"

  if [[ -z "$key_id" ]]; then
    # Collect secret key IDs
    local -a key_ids=()
    local -a key_labels=()
    while IFS= read -r line; do
      # Lines look like: sec   ed25519/AABBCCDD1122 2024-01-01 [SC]
      local kid
      kid=$(echo "$line" | sed -n 's|^sec[[:space:]]\+[^/]*/\([A-F0-9]\+\).*|\1|p')
      [[ -n "$kid" ]] || continue
      key_ids+=("$kid")
      key_labels+=("$line")
    done < <($gpg_bin --list-secret-keys --keyid-format=long 2> /dev/null | grep '^sec')

    if ((${#key_ids[@]} == 0)); then
      echo "No GPG secret keys found. Generate one first:" >&2
      echo "  gpg --full-generate-key" >&2
      return 1
    elif ((${#key_ids[@]} == 1)); then
      key_id="${key_ids[1]:-${key_ids[0]}}"
      echo "Auto-selected GPG key: $key_id"
    else
      echo "Available GPG secret keys:"
      local i
      for i in "${!key_labels[@]}"; do
        local idx=$((i + 1))
        # Show the sec line + the uid line
        printf "  [%d] %s\n" "$idx" "${key_labels[$i]}"
        $gpg_bin --list-secret-keys --keyid-format=long 2> /dev/null \
          | grep -A 2 "${key_ids[$i]}" | grep '^uid' | head -1 \
          | sed 's/^/      /'
      done
      echo ""
      printf "Select key [1-%d]: " "${#key_ids[@]}"
      local choice
      read -r choice
      if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#key_ids[@]})); then
        key_id="${key_ids[$((choice))]:-${key_ids[$((choice - 1))]}}"
      else
        echo "Invalid selection." >&2
        return 1
      fi
    fi
  fi

  # Validate the key exists
  if ! $gpg_bin --list-secret-keys --keyid-format=long 2> /dev/null | grep -q "$key_id"; then
    echo "Error: GPG secret key '$key_id' not found." >&2
    return 1
  fi

  # Configure git
  git config --global user.signingkey "$key_id"
  git config --global commit.gpgsign true
  git config --global tag.gpgSign true
  git config --global gpg.program "$gpg_bin"

  echo "GPG signing configured:"
  echo "  user.signingkey  = $key_id"
  echo "  commit.gpgsign   = true"
  echo "  tag.gpgSign      = true"
  echo "  gpg.program      = $gpg_bin"
}

# Get the current GPG signing key ID (from git config or auto-detect).
# Usage:
#   get_gpg_key          # prints the key ID
#   key=$(get_gpg_key)   # capture into a variable
get_gpg_key() {
  local key
  key=$(git config --global user.signingkey 2> /dev/null || true)
  if [[ -z "$key" ]]; then
    local gpg_bin
    if command -v gpg2 &> /dev/null; then
      gpg_bin=gpg2
    elif command -v gpg &> /dev/null; then
      gpg_bin=gpg
    else return 1; fi
    key=$($gpg_bin --list-secret-keys --keyid-format=long 2> /dev/null \
      | grep '^sec' | head -1 \
      | sed -n 's|^sec[[:space:]]\+[^/]*/\([A-F0-9]\+\).*|\1|p')
  fi
  [[ -n "$key" ]] && echo "$key" || return 1
}

ght() {
  printf '%s' "$GITHUB_PAT" | xclip -sel clip
  echo "Token copied to clipboard!"
}

ghk() {
  printf '%s' "$GITHUB_KAYAMAN_PAT" | xclip -sel clip
  echo "Token copied to clipboard!"
}
