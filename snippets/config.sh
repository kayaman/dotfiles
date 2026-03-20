#!/usr/bin/env bash
# snippet: config.sh - Load dotfiles.toml configuration and secrets

config_file="$DOTFILES/dotfiles.toml"
[[ -f "$config_file" ]] || return 0

# Use python to safely parse TOML and export [secrets] as env vars
# Requires Python 3.11+ for built-in 'tomllib', or 'toml' library installed
eval $(python3 -c "
import sys
import os

def load_config(file_path):
    try:
        import tomllib
    except ImportError:
        try:
            import toml as tomllib
        except ImportError:
            return {}
    
    try:
        with open(file_path, 'rb') as f:
            return tomllib.load(f)
    except Exception:
        return {}

data = load_config('$config_file')

# Load secrets into environment variables
if 'secrets' in data and isinstance(data['secrets'], dict):
    for k, v in data['secrets'].items():
        if isinstance(v, (str, int, float, bool)):
            # Print as export command
            print(f'export {k}=\"{v}\"')

" 2>/dev/null)
