#!/usr/bin/env zsh
# Catch-all: dev environments, network/processes, containers, small utilities.

# ── Dev environments ─────────────────────────────────────────

# Create and activate a venv in current dir
mkvenv() {
  local name="${1:-.venv}"
  python3 -m venv "$name"
  source "$name/bin/activate"
  pip install --upgrade pip setuptools wheel
  echo "Activated $name ($(python3 --version))"
}

# Bootstrap a strict TypeScript project
tsinit() {
  local name="${1:-.}"
  if [[ "$name" != "." ]]; then
    mkdir -p "$name" && cd "$name"
  fi
  npm init -y
  npm install --save-dev typescript @types/node ts-node
  npx tsc --init --target ES2022 --module NodeNext \
    --moduleResolution NodeNext --strict --esModuleInterop \
    --outDir ./dist --rootDir ./src
  mkdir -p src
  echo 'console.log("Hello, TypeScript!");' > src/index.ts
  echo "TypeScript project initialized in $(pwd)"
}

# Convert uv-managed deps to requirements.txt
uv2req() {
  if ! command -v uv > /dev/null 2>&1; then
    printf 'uv2req: uv is not installed or not in PATH\n' >&2
    return 1
  fi

  local tmpfile
  tmpfile="$(mktemp requirements.txt.XXXXXX)" || {
    printf 'uv2req: failed to create temporary file\n' >&2
    return 1
  }

  if ! uv export --format requirements-txt --no-dev --no-hashes > "$tmpfile"; then
    printf 'uv2req: uv export failed; requirements.txt not updated\n' >&2
    rm -f "$tmpfile"
    return 1
  fi

  mv "$tmpfile" requirements.txt
}

# ── Network / HTTP / processes ───────────────────────────────

# Quick HTTP server
serve() {
  local port="${1:-8000}"
  echo "Serving on http://localhost:$port"
  python3 -m http.server "$port"
}

# Find process by name
psg() {
  ps aux | head -1
  ps aux | grep -v grep | grep -i "$@"
}

killport() {
  if [[ -z "$1" ]]; then
    echo "Usage: killport <port>"
    return 1
  fi
  local pid
  pid="$(lsof -ti:"$1" 2> /dev/null)"
  if [[ -n "$pid" ]]; then
    kill "$pid" && echo "Killed process $pid on port $1"
  else
    echo "No process found on port $1"
  fi
}

# List processes on port (use killport to kill)
portlist() { ss -tulnp 2> /dev/null | grep ":$1" || netstat -tulpn 2> /dev/null | grep ":$1"; }
fpp() { ss -ltnp 2> /dev/null | grep -w "$1" || netstat -ltnp 2> /dev/null | grep -w "$1"; }

# Find and kill process by name (works alongside Oh My Zsh)
fkill() {
  local pid
  if [[ "$UID" != "0" ]]; then
    pid=$(ps -f -u "$UID" | sed 1d | fzf -m | awk '{print $2}')
  else
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
  fi

  if [[ -n "$pid" ]]; then
    echo "$pid" | xargs kill -"${1:-9}"
  fi
}

openfiles() { awk '{print $1}' /proc/sys/fs/file-nr; }
usage() { sudo lsof -p "$(pidof "$1")"; }

# Memory usage of processes
mem_usage() {
  ps aux | awk '{print $6/1024 " MB\t\t" $11}' | sort -n
}

# Cheap presence check
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

nmap_() {
  nmap -sS -O -p- "${1:-192.168.15.0/24}"
}

# ── Kubernetes (kpf comes from oh-my-zsh kubectl plugin) ─────

kurl() { kubectl run curl-debug --image=curlimages/curl -i --tty --rm -- sh; }
kexec() { kubectl exec -it "$1" -- /bin/bash; }
klogs() { kubectl logs -f "$1"; }

# ── Containers ───────────────────────────────────────────────

dcsr() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: dcsr CONTAINER [CONTAINER...]" >&2
    return 1
  fi
  docker container rm -f -- "$@"
}

lint() { podman run -v "$(pwd):/code" ghcr.io/biomejs/biome lint; }
lint-fix() { podman run -v "$(pwd):/code" ghcr.io/biomejs/biome lint --write; }
format-dry-run() { podman run -v "$(pwd):/code" ghcr.io/biomejs/biome format; }
format() { podman run -v "$(pwd):/code" ghcr.io/biomejs/biome format --write; }

# ── Misc utilities ───────────────────────────────────────────

# Weather
wttr() { curl -s "wttr.in/${1:-}?format=3"; }

# Quick note (writes to ~/notes/YYYY-MM-DD.md)
note() {
  local notes_dir="$HOME/notes"
  mkdir -p "$notes_dir"
  if [[ $# -eq 0 ]]; then
    "${EDITOR:-vim}" "$notes_dir/$(date +%Y-%m-%d).md"
  else
    echo "$(date +%H:%M) — $*" >> "$notes_dir/$(date +%Y-%m-%d).md"
    echo "Note added."
  fi
}

# Colored man (wrapper; uses command man internally)
man() {
  LESS_TERMCAP_md=$'\e[1;36m' \
    LESS_TERMCAP_me=$'\e[0m' \
    LESS_TERMCAP_us=$'\e[1;32m' \
    LESS_TERMCAP_ue=$'\e[0m' \
    LESS_TERMCAP_so=$'\e[1;33;44m' \
    LESS_TERMCAP_se=$'\e[0m' \
    command man "$@"
}

# Semver release: branch, PR, merge, tag, gh release (no confirmation)
ship() {
  local usage="Usage: ship <major|minor|patch> [commit message]"
  local bump="${1:-}"
  local msg="${2:-}"

  if [[ -z "$bump" ]]; then
    echo "$usage" >&2
    return 1
  fi

  case "$bump" in
    major | minor | patch) ;;
    *)
      echo "Error: bump must be major, minor, or patch" >&2
      echo "$usage" >&2
      return 1
      ;;
  esac

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: not inside a git repository" >&2
    return 1
  fi

  if ! command -v gh > /dev/null 2>&1; then
    echo "Error: gh CLI not found" >&2
    return 1
  fi

  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  local latest_tag
  latest_tag="$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)"

  local major=0 minor=0 patch=0
  if [[ -n "$latest_tag" ]]; then
    IFS='.' read -r major minor patch <<< "${latest_tag#v}"
  fi

  case "$bump" in
    major)
      ((major++))
      minor=0
      patch=0
      ;;
    minor)
      ((minor++))
      patch=0
      ;;
    patch) ((patch++)) ;;
  esac

  local new_version="v${major}.${minor}.${patch}"

  if [[ -n "$(git status --porcelain)" ]]; then
    if [[ -z "$msg" ]]; then
      echo "Error: working tree has uncommitted changes — provide a commit message as \$2" >&2
      return 1
    fi
    git add -A
    git commit -m "$msg"
  fi

  local branch="release/${new_version}"
  git checkout -b "$branch"
  git push -u origin "$branch"

  local pr_url
  pr_url="$(gh pr create \
    --title "release: ${new_version}" \
    --body "Release ${new_version} (${bump} bump from ${latest_tag:-none})" \
    --base main \
    --head "$branch" \
    --label "release" 2> /dev/null \
    || gh pr create \
      --title "release: ${new_version}" \
      --body "Release ${new_version} (${bump} bump from ${latest_tag:-none})" \
      --base main \
      --head "$branch")"

  echo "PR created: $pr_url"

  if ! gh pr merge --squash --delete-branch; then
    echo "Error: PR merge failed — aborting release" >&2
    git checkout main
    return 1
  fi

  git checkout main
  git pull

  git tag -a "$new_version" -m "Release ${new_version}"
  git push origin "$new_version"

  gh release create "$new_version" \
    --title "Release ${new_version}" \
    --generate-notes

  echo "Released ${new_version}"
}

# JSON pretty print and query
json() {
  if [[ $# -eq 0 ]]; then
    jq . 2> /dev/null || python3 -m json.tool
  else
    jq "$@" 2> /dev/null || echo "jq not available"
  fi
}

# Edit ~/.aliases in $EDITOR; then re-source.
aliases() {
  local editor aliases_file
  editor="${VISUAL:-${EDITOR:-vi}}"

  if [[ -n "$DOTFILES" && -f "$DOTFILES/.aliases" ]]; then
    aliases_file="$DOTFILES/.aliases"
  elif [[ -f "$HOME/.aliases" ]]; then
    aliases_file="$HOME/.aliases"
  else
    aliases_file="${DOTFILES:-$HOME}/.aliases"
  fi

  "$editor" "$aliases_file"
  src
}

# Create a data URL from a file
dataurl() {
  local mimeType=$(file -b --mime-type "$1")
  if [[ $mimeType == text/* ]]; then
    mimeType="${mimeType};charset=utf-8"
  fi
  echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')"
}

# Random 16-byte hex string
random() {
  echo "$(openssl rand -hex 16)"
}

# Create or attach a tmux session
tm() {
  local session=${1:-main}
  if ! tmux has-session -t="$session" 2> /dev/null; then
    tmux new-session -s "$session"
  else
    tmux attach-session -t "$session"
  fi
}

# Update dotfiles. Prefer `dot update` (richer output + dry-run).
update_dotfiles() {
  (cd ~/Projects/dotfiles && git pull && ./install.sh)
  echo "Dotfiles updated"
}

# ── Installers / auth helpers ────────────────────────────────

install_claude_code() {
  curl -fsSL https://claude.ai/install.sh | bash
  echo "Installation complete"
}

install_gemini() {
  npm install -g @google/gemini-cli
}

eval_ssh_agent() {
  eval "$(ssh-agent -s)"
}

get_ai_gtw_pass() {
  aws ssm get-parameter --name /ai-gateway/admin_token --with-decryption --query Parameter.Value --output text
}

exec-logs() {
  journalctl -u executor@kayaman -f
}
