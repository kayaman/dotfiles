#!/usr/bin/env bash
# snippet: config.sh - Load dotfiles configuration and secrets via SOPS or plain TOML

config_file="$DOTFILES/dotfiles.toml"
sops_file="$DOTFILES/dotfiles.sops.toml"

# Determine which file to load
if [[ -f "$sops_file" ]] && command -v sops &> /dev/null; then
  content=$(sops -d "$sops_file" 2> /dev/null) || return 0
elif [[ -f "$config_file" ]]; then
  content=$(cat "$config_file" 2> /dev/null) || return 0
else
  return 0
fi

# Use python to safely parse TOML and export [secrets] as env vars
eval "$(echo "$content" | python3 -c "
import sys

def load_config(text):
    try:
        import tomllib
    except ImportError:
        try:
            import toml as tomllib
        except ImportError:
            return {}
    try:
        return tomllib.loads(text)
    except Exception:
        return {}

content = sys.stdin.read()
data = load_config(content)

# Load secrets into environment variables
if 'secrets' in data and isinstance(data['secrets'], dict):
    for k, v in data['secrets'].items():
        if isinstance(v, (str, int, float, bool)):
            print(f'export {k}=\"{v}\"')
" 2> /dev/null)"
