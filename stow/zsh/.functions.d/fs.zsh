#!/usr/bin/env zsh
# Filesystem, navigation, file-search, and viewing helpers.

# ── Navigation ───────────────────────────────────────────────

# Create dir and cd into it
mkcd() { mkdir -p "$1" && cd "$1"; }

# Interactive cd with fzf
cdf() {
  local dir
  dir="$(fd --type d --hidden --follow --exclude .git 2> /dev/null | fzf --preview 'eza --tree --level=1 --icons {}')" \
    && cd "$dir"
}

p() {
  cd ~/Projects/"$1"
}

# Go to git repo root
groot() { cd "$(git rev-parse --show-toplevel 2> /dev/null || echo '.')"; }

# $_ = last arg of previous command (mkdir)
mk() { mkdir -p "$@" && cd "$_"; }

# ── File search ──────────────────────────────────────────────

# Open file found with fzf in $EDITOR
fe() {
  local file
  file="$(fzf --preview 'bat --color=always --style=numbers --line-range=:100 {}')" \
    && "${EDITOR:-vim}" "$file"
}

# Ripgrep + fzf for interactive code search
rgi() {
  local result
  result="$(rg --color=always --line-number --no-heading "$@" 2> /dev/null \
    | fzf --ansi --delimiter ':' \
      --preview 'bat --color=always --highlight-line {2} {1}' \
      --preview-window '+{2}/2')" || return
  local file line
  file="$(echo "$result" | cut -d: -f1)"
  line="$(echo "$result" | cut -d: -f2)"
  "${EDITOR:-vim}" "+${line}" "$file"
}

# Find files by extension
findext() {
  find . -type f -name "*.$1" | sort
}

# Find large files
findbig() {
  local size="${1:-100M}"
  echo "Finding files larger than $size..."
  find . -type f -size +"$size" -exec ls -lh {} \; 2> /dev/null | awk '{print $5 " " $9}' | sort -hr
}

# Count files in directory
count() {
  find "${1:-.}" -type f | wc -l
}

# ── Viewing ──────────────────────────────────────────────────

preview() {
  if [[ -f "$1" ]]; then
    bat "$1" 2> /dev/null || cat "$1"
  elif [[ -d "$1" ]]; then
    eza --tree --level=2 --icons "$1" 2> /dev/null || ls -la "$1"
  else
    echo "Usage: preview <file_or_directory>"
  fi
}

# Use `tree` with the global ignore patterns in ~/.treeglobal if present.
tree() {
  if [ -f "$HOME/.treeglobal" ]; then
    command tree -I "$(paste -d\| -s "$HOME/.treeglobal")" "$@"
  else
    command tree "$@"
  fi
}

# ── Extract / backup ─────────────────────────────────────────

extract() {
  if [[ ! -f "$1" ]]; then
    echo "Error: '$1' is not a valid file" >&2
    return 1
  fi
  case "$1" in
    *.tar.bz2) tar xjf "$1" ;;
    *.tar.gz) tar xzf "$1" ;;
    *.tar.xz) tar xJf "$1" ;;
    *.tar.zst) tar --zstd -xf "$1" ;;
    *.bz2) bunzip2 "$1" ;;
    *.gz) gunzip "$1" ;;
    *.tar) tar xf "$1" ;;
    *.tbz2) tar xjf "$1" ;;
    *.tgz) tar xzf "$1" ;;
    *.zip) unzip "$1" ;;
    *.Z) uncompress "$1" ;;
    *.7z) 7z x "$1" ;;
    *.rar) unrar x "$1" ;;
    *)
      echo "Cannot extract '$1': unknown format" >&2
      return 1
      ;;
  esac
}

# Timestamped backup
bak() {
  if [[ -z "$1" ]]; then
    echo "Usage: bak <file>"
    return 1
  fi
  cp "$1" "$1.bak-$(date +%Y%m%d-%H%M%S)"
  echo "Backed up $1"
}

# Sibling .bak file (no timestamp)
backup() {
  cp "$1"{,.bak}
}
