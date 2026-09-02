#!/usr/bin/env zsh
# `dot` — dotfiles sync manager. See `dot help` for the authoritative
# command list. The helper `_dot_toml_get` lives here too because it's
# only used by `dot config`.

# _dot_toml_get <file> <section> <key>
#   Reads a bare (unquoted) value from a TOML file.
#   Supports quoted strings, integers, booleans; one value per line.
#   Does NOT support multi-line values, arrays, or inline tables.
#
#   Example:
#     _dot_toml_get ~/Projects/dotfiles/dotfiles.toml git signingkey
#     _dot_toml_get ~/Projects/dotfiles/dotfiles.toml secrets GITHUB_TOKEN
_dot_toml_get() {
  local file="$1" section="$2" key="$3"
  [[ -f "$file" ]] || {
    echo "_dot_toml_get: file not found: $file" >&2
    return 1
  }
  awk -v section="$section" -v key="$key" '
        /^\[/ {
            current = substr($0, 2, length($0)-2)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", current)
        }
        current == section && /^[[:space:]]*[^#]/ {
            if (match($0, /^[[:space:]]*[^=[:space:]]+[[:space:]]*=[[:space:]]*/)) {
                k = substr($0, 1, RLENGTH)
                gsub(/^[[:space:]]+|[[:space:]]*=[[:space:]]*$/, "", k)
                if (k == key) {
                    v = substr($0, RLENGTH + 1)
                    gsub(/#[^"]*$/, "", v)
                    gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", v)
                    print v
                    found = 1
                    exit 0
                }
            }
        }
        END { exit (found ? 0 : 1) }
    ' "$file"
}

# -- dot -- dotfiles sync manager --
# Usage:  dot [command] [args]
# Secrets: add ERE patterns to $DOTFILES/.dotfilter (one per line).
# Lines matching any pattern are replaced with '# [REDACTED by dot-filter]'
# in the git index at git-add time. Working-tree files are NEVER modified.
# Run: dot filter-install  (once per machine to activate secret redaction)

dot() {
  local DOTFILES="${DOTFILES:-$HOME/Projects/dotfiles}"
  local DOTFILTER="$DOTFILES/.dotfilter"
  local _r='\033[0;31m' _g='\033[0;32m' _y='\033[1;33m'
  local _c='\033[0;36m' _b='\033[1m' _n='\033[0m'
  local _ok="  ${_g}v${_n}" _err="  ${_r}x${_n}" _info="  ${_c}->${_n}"

  # Accept both a regular repo (.git/) and a worktree (.git is a file).
  if [[ ! -e "$DOTFILES/.git" ]]; then
    echo -e "${_r}Error:${_n} $DOTFILES is not a git repository." >&2
    return 1
  fi

  local cmd="${1:-}"
  shift 2> /dev/null || true

  case "$cmd" in

    help | --help | -h | "")
      echo -e "${_b}dot${_n} -- dotfiles sync manager"
      echo ""
      echo -e "${_b}USAGE${_n}"
      echo "  dot <command> [args]"
      echo ""
      echo -e "${_b}COMMANDS${_n}"
      printf "  ${_c}%-22s${_n} %s\n" \
        "sync [msg]" "Commit local changes, pull --rebase, push" \
        "push [msg]" "Commit all changes and push to origin" \
        "pull" "Pull from origin and re-apply stow links" \
        "status" "git status + ahead/behind origin" \
        "diff" "Uncommitted diff (staged + unstaged)" \
        "edit" "Open dotfiles repo in EDITOR / code" \
        "cd" "cd into the dotfiles directory" \
        "doctor" "Run health checks against the local install" \
        "update" "Pull, re-stow, and dry-run the installer" \
        "filter-show" "List active .dotfilter patterns" \
        "filter-add <p>" "Append an ERE pattern to .dotfilter" \
        "filter-install" "Register git clean filter on this machine" \
        "config get <s.k>" "Read a value from dotfiles.toml (section.key)" \
        "config list [s]" "List keys in a section (or all sections)" \
        "config apply" "Export [secrets] into the current shell" \
        "check" "Dry-run: show lines that would be redacted" \
        "profiler" "Profile shell startup time (sorted slowest-first)" \
        "profiler --raw" "Show raw profiling log"
      echo ""
      echo -e "${_b}CONFIG (dotfiles.toml)${_n}"
      echo "  dot config get  git.signingkey"
      echo "  dot config get  secrets.GITHUB_TOKEN"
      echo "  dot config list secrets"
      echo "  dot config apply          # exports [secrets] into current shell"
      echo ""
      echo -e "${_b}SECRET-LINE IGNORING (.dotfilter)${_n}"
      echo "  Add ERE patterns (one per line) to DOTFILES/.dotfilter."
      echo "  Matching lines are replaced with '# [REDACTED by dot-filter]'"
      echo "  in the git index. Working-tree files are never modified."
      echo ""
      echo "  Example .dotfilter entries:"
      echo "    signingkey\s*=.*"
      echo "    GITHUB_TOKEN\s*=.*"
      echo "    password\s*=.*"
      echo ""
      echo "  Run: dot filter-install (once per machine)"
      ;;

    cd)
      cd "$DOTFILES"
      ;;

    edit)
      local editor="${VISUAL:-${EDITOR:-}}"
      if [[ -z "$editor" ]]; then
        if command -v code &> /dev/null; then
          editor="code"
        elif command -v nvim &> /dev/null; then
          editor="nvim"
        else editor="vi"; fi
      fi
      "$editor" "$DOTFILES"
      ;;

    status)
      echo -e "${_b}Dotfiles:${_n} $DOTFILES"
      (
        cd "$DOTFILES" && git fetch -q 2> /dev/null
        git status -sb
      )
      echo ""
      local behind ahead
      behind=$(cd "$DOTFILES" && git rev-list --count HEAD..@{u} 2> /dev/null || echo 0)
      ahead=$(cd "$DOTFILES" && git rev-list --count @{u}..HEAD 2> /dev/null || echo 0)
      [[ "$ahead" -gt 0 ]] && echo -e "$_info ${_y}${ahead} commit(s) ahead${_n} of origin"
      [[ "$behind" -gt 0 ]] && echo -e "$_info ${_r}${behind} commit(s) behind${_n} -- run: dot pull"
      [[ "$ahead" -eq 0 && "$behind" -eq 0 ]] && echo -e "$_ok In sync with origin"
      ;;

    diff)
      (cd "$DOTFILES" && git diff --color=always && git diff --cached --color=always)
      ;;

    pull)
      echo -e "$_info Pulling from origin..."
      (cd "$DOTFILES" && git pull --rebase --autostash) || {
        echo -e "$_err Pull failed. Resolve conflicts then: dot push" >&2
        return 1
      }
      echo -e "$_ok Pull complete."
      if command -v stow &> /dev/null && [[ -d "$DOTFILES/stow" ]]; then
        echo -e "$_info Re-applying stow links..."
        (cd "$DOTFILES" && stow --dir="$DOTFILES/stow" --target="$HOME" \
          --restow $(ls stow) 2> /dev/null) \
          && echo -e "$_ok Stow links updated." \
          || echo -e "${_y}[WARN]${_n}  stow failed; run install.sh manually."
      fi
      ;;

    push)
      local msg="${*:-chore: sync dotfiles $(date +%Y-%m-%d)}"
      (
        cd "$DOTFILES"
        if [[ -z "$(git status --porcelain)" ]]; then
          echo -e "$_ok Nothing to commit."
        else
          git add -A
          echo -e "$_info Committing: \"$msg\""
          git commit -m "$msg" || {
            echo -e "$_err Commit failed (pre-commit hook?). Aborting." >&2
            return 1
          }
        fi
        echo -e "$_info Pushing..."
        git push && echo -e "$_ok Push complete."
      )
      ;;

    sync)
      local msg="${*:-chore: sync dotfiles $(date +%Y-%m-%d)}"
      (
        cd "$DOTFILES"
        if [[ -n "$(git status --porcelain)" ]]; then
          echo -e "$_info Committing local changes..."
          git add -A
          git commit -m "$msg" || {
            echo -e "$_err Commit failed (pre-commit hook?). Aborting." >&2
            return 1
          }
          echo -e "$_ok Committed."
        fi
        echo -e "$_info Pulling (rebase)..."
        git pull --rebase --autostash || {
          echo -e "$_err Rebase conflict. Resolve then: dot push" >&2
          return 1
        }
        echo -e "$_info Pushing..."
        git push && echo -e "$_ok Sync complete."
      )
      ;;

    doctor)
      _dot_doctor "$DOTFILES"
      ;;

    update)
      _dot_update "$DOTFILES"
      ;;

    filter-show)
      if [[ ! -f "$DOTFILTER" ]]; then
        echo -e "${_y}No .dotfilter.${_n} Add patterns: dot filter-add <pattern>"
        return 0
      fi
      echo -e "${_b}$DOTFILTER:${_n}"
      grep -v '^\s*#' "$DOTFILTER" | grep -v '^\s*$' \
        | while IFS= read -r p; do echo "  $p"; done
      ;;

    filter-add)
      local pattern="${*}"
      if [[ -z "$pattern" ]]; then
        echo "Usage: dot filter-add <ERE pattern>" >&2
        return 1
      fi
      echo "$pattern" >> "$DOTFILTER"
      echo -e "$_ok Pattern added: $pattern"
      ;;

    filter-install)
      # Logic lives in scripts/filter-install.sh so install.sh can register
      # the filter during bootstrap too.
      bash "$DOTFILES/scripts/filter-install.sh"
      ;;

    config)
      local TOML="$DOTFILES/dotfiles.toml"
      local subcmd="${1:-}"
      shift 2> /dev/null || true
      case "$subcmd" in

        get)
          local ref="${1:-}"
          if [[ -z "$ref" || "$ref" != *.* ]]; then
            echo "Usage: dot config get <section>.<key>" >&2
            return 1
          fi
          local sec="${ref%%.*}" key="${ref#*.}"
          if [[ ! -f "$TOML" ]]; then
            echo -e "${_r}Not found:${_n} $TOML" >&2
            echo "Copy dotfiles.toml.example -> dotfiles.toml and fill in values." >&2
            return 1
          fi
          local val
          val=$(_dot_toml_get "$TOML" "$sec" "$key") || {
            echo -e "${_r}Not found:${_n} [$sec] $key in $TOML" >&2
            return 1
          }
          echo "$val"
          ;;

        list)
          local sec="${1:-}"
          if [[ ! -f "$TOML" ]]; then
            echo -e "${_r}Not found:${_n} $TOML" >&2
            return 1
          fi
          if [[ -z "$sec" ]]; then
            grep -E '^\[' "$TOML" | tr -d '[]' | while IFS= read -r s; do
              echo -e "  ${_c}[$s]${_n}"
            done
          else
            awk -v section="$sec" '
                    /^\[/ {
                        current = substr($0,2,length($0)-2)
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", current)
                    }
                    current == section && /^[[:space:]]*[^#\[]/ {
                        line = $0
                        gsub(/^[[:space:]]+/, "", line)
                        if (line != "") print "  " line
                    }
                ' "$TOML"
          fi
          ;;

        apply)
          if [[ ! -f "$TOML" ]]; then
            echo -e "${_r}Not found:${_n} $TOML" >&2
            return 1
          fi
          local count=0
          while IFS= read -r rawline; do
            [[ -z "$rawline" || "$rawline" == \#* ]] && continue
            local k v
            k="${rawline%%=*}"
            k="${k//[[:space:]]/}"
            v="${rawline#*=}"
            v="${v%%\#*}"
            v="${v#"${v%%[! ]*}"}"
            v="${v%"${v##*[! ]}"}"
            v="${v#[\'\"]}"
            v="${v%[\'\"]}"
            export "$k=$v"
            echo -e "$_ok Exported ${_y}${k}${_n}"
            ((count++))
          done < <(awk '
                /^\[/ { current = substr($0,2,length($0)-2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",current) }
                current == "secrets" && /^[[:space:]]*[^#]/ && /=/ { print $0 }
            ' "$TOML")
          [[ "$count" -eq 0 ]] && echo -e "${_y}No entries in [secrets] section.${_n}"
          ;;

        *)
          echo "Usage: dot config <get <section.key> | list [section] | apply>" >&2
          return 1
          ;;
      esac
      ;;

    check)
      if [[ ! -f "$DOTFILTER" ]]; then
        echo -e "${_y}No .dotfilter.${_n} Nothing would be redacted."
        return 0
      fi
      local patterns=()
      while IFS= read -r p; do
        [[ -z "$p" || "$p" == \#* ]] && continue
        patterns+=("$p")
      done < "$DOTFILTER"
      [[ ${#patterns[@]} -eq 0 ]] && {
        echo "No active patterns."
        return 0
      }
      echo -e "${_b}Lines that would be redacted:${_n}"
      local found=0
      while IFS= read -r file; do
        for pat in "${patterns[@]}"; do
          local hits
          hits=$(grep -nEi "$pat" "$DOTFILES/$file" 2> /dev/null) || continue
          echo -e "  ${_y}$file${_n}"
          echo "$hits" | sed "s/^/    /"
          found=1
        done
      done < <(cd "$DOTFILES" && git ls-files)
      [[ "$found" -eq 0 ]] && echo -e "$_ok No matching lines in tracked files."
      ;;

    profiler)
      local raw=false
      [[ "${1:-}" == "--raw" ]] && raw=true

      local logfile="/tmp/zsh-profile-$$.log"
      : > "$logfile"

      echo -e "${_b}Profiling shell startup...${_n}"
      ZSH_PROF=1 ZSH_PROF_LOG="$logfile" zsh -i -c 'exit' 2> /dev/null

      if [[ ! -s "$logfile" ]]; then
        echo -e "${_r}Error:${_n} No profiling data captured." >&2
        rm -f "$logfile"
        return 1
      fi

      if $raw; then
        echo -e "\n${_b}Raw profiling log:${_n}"
        column -t -s $'\t' < "$logfile"
        rm -f "$logfile"
        return 0
      fi

      # ── Parse source:begin/end pairs and render table ──
      awk -F'\t' '
                BEGIN {
                    n = 0
                }
                {
                    elapsed = $1 + 0
                    delta   = $2 + 0
                    label   = $3
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)

                    # source:begin — record start time, skip row
                    if (label ~ /^source:begin /) {
                        sub(/^source:begin[[:space:]]+/, "", label)
                        begin_time[label] = elapsed
                        next
                    }

                    # source:end — compute duration from matching begin
                    if (label ~ /^source:end[[:space:]]+/) {
                        sub(/^source:end[[:space:]]+/, "", label)
                        if (label in begin_time) {
                            delta = elapsed - begin_time[label]
                            delete begin_time[label]
                        }
                        prefix = "  \033[2m\xe2\x86\xb3\033[0m "
                    } else {
                        prefix = ""
                    }

                    labels[n]   = prefix label
                    deltas[n]   = delta
                    times[n]    = elapsed
                    n++
                }
                END {
                    if (n == 0) { print "No data."; exit 1 }
                    total = times[n-1]
                    if (total <= 0) total = 1

                    # Insertion-sort by delta descending
                    for (i = 0; i < n; i++) idx[i] = i
                    for (i = 1; i < n; i++) {
                        j = i
                        while (j > 0 && deltas[idx[j-1]] < deltas[idx[j]]) {
                            tmp = idx[j-1]; idx[j-1] = idx[j]; idx[j] = tmp
                            j--
                        }
                    }

                    # Header
                    printf "\n"
                    printf "\033[1m %-4s  %9s  %5s  %-20s  %s\033[0m\n", \
                           "#", "TIME", "%", "BAR", "STEP"
                    printf " %-4s  %9s  %5s  %-20s  %s\n", \
                           "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80", \
                           "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80", \
                           "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80", \
                           "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80", \
                           "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80"

                    bar_max = 20
                    max_delta = 0
                    for (i = 0; i < n; i++)
                        if (deltas[i] > max_delta) max_delta = deltas[i]
                    if (max_delta <= 0) max_delta = 1

                    for (rank = 0; rank < n; rank++) {
                        i = idx[rank]
                        d = deltas[i]
                        pct = (d / total) * 100

                        # Color: red >100ms, yellow >30ms, green <30ms
                        if (d > 100)     color = "\033[0;31m"
                        else if (d > 30) color = "\033[1;33m"
                        else             color = "\033[0;32m"
                        nc = "\033[0m"

                        bar_len = int((d / max_delta) * bar_max + 0.5)
                        if (bar_len < 1 && d > 0.01) bar_len = 1
                        bar = ""
                        for (b = 0; b < bar_len; b++) bar = bar "\xe2\x96\x88"

                        printf " %s%-4d%s  %s%8.2fms%s  %4.1f%%  %s%-20s%s  %s\n", \
                               color, rank+1, nc, \
                               color, d, nc, \
                               pct, \
                               color, bar, nc, \
                               labels[i]
                    }

                    printf "\n \033[1mTotal startup: %.0fms\033[0m\n", total
                }
                ' "$logfile"
      echo ""
      rm -f "$logfile"
      ;;

    *)
      echo -e "${_r}Unknown command:${_n} $cmd" >&2
      echo "Run: dot help" >&2
      return 1
      ;;
  esac
}

# ── dot subcommands extracted as helpers ─────────────────────
# These are stubs in this file; 3.1 and 3.2 wire them up to real checks.

_dot_doctor() {
  local DOTFILES="${1:-${DOTFILES:-$HOME/Projects/dotfiles}}"
  local _r='\033[0;31m' _g='\033[0;32m' _y='\033[1;33m' _n='\033[0m'
  local pass="${_g}PASS${_n}" warn="${_y}WARN${_n}" fail="${_r}FAIL${_n}"
  local rc=0

  _check() { # _check <label> <ok-bool> <detail>
    local label="$1" ok="$2" detail="${3:-}"
    if [[ "$ok" == "true" ]]; then
      printf "  [%b] %s\n" "$pass" "$label"
    elif [[ "$ok" == "warn" ]]; then
      printf "  [%b] %s  %s\n" "$warn" "$label" "$detail"
    else
      printf "  [%b] %s  %s\n" "$fail" "$label" "$detail"
      rc=1
    fi
  }

  echo "dot doctor — checking $DOTFILES"
  echo ""

  # 1. Stow symlinks: every package file under stow/ should be reachable
  # from $HOME and resolve to the same inode in the repo. Stow folds
  # whole directories when possible, so the symlink can live at any
  # ancestor — comparing canonical paths handles all cases.
  local pkg link broken=0 total=0
  for pkg in "$DOTFILES"/stow/*/; do
    while IFS= read -r -d '' f; do
      local rel="${f#"$pkg"}"
      link="$HOME/$rel"
      total=$((total + 1))
      if [[ ! -e "$link" ]]; then
        broken=$((broken + 1))
      elif [[ "$(readlink -f "$link" 2> /dev/null)" != "$(readlink -f "$f" 2> /dev/null)" ]]; then
        broken=$((broken + 1))
      fi
    done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \) -print0 2> /dev/null)
  done
  if ((broken == 0)); then
    _check "stow links ($total checked)" true
  else
    _check "stow links" false "$broken/$total link(s) missing or pointing elsewhere — run: install.sh"
  fi

  # 2. Required CLI tools.
  local required=(stow git eza bat fzf rg fd delta gh) missing=()
  for t in "${required[@]}"; do
    command -v "$t" &> /dev/null || missing+=("$t")
  done
  if ((${#missing[@]} == 0)); then
    _check "required tools" true
  else
    _check "required tools" false "missing: ${missing[*]} — run: install.sh"
  fi

  # 3. .dotfilter git clean filter installed.
  local filter_clean
  filter_clean=$(cd "$DOTFILES" && git config --get filter.dot-secrets.clean 2> /dev/null)
  if [[ -n "$filter_clean" && -x "$filter_clean" ]]; then
    _check ".dotfilter clean filter" true
  elif [[ -f "$DOTFILES/.dotfilter" ]]; then
    _check ".dotfilter clean filter" warn "patterns exist but hook not installed — run: dot filter-install"
  else
    _check ".dotfilter clean filter" warn "no .dotfilter file (no secrets to redact?)"
  fi

  # 4. Shell startup under 500ms.
  local ms
  ms=$(/usr/bin/time -f '%e' zsh -i -c exit 2>&1 | tail -1)
  ms=$(awk -v s="$ms" 'BEGIN { printf "%d", s * 1000 }')
  if ((ms < 500)); then
    _check "zsh startup ($ms ms)" true
  elif ((ms < 1000)); then
    _check "zsh startup ($ms ms)" warn "above 500ms target — run: dot profiler"
  else
    _check "zsh startup ($ms ms)" false "above 1s — run: dot profiler"
  fi

  # 5. dotfiles.toml parses (if present).
  if [[ -f "$DOTFILES/dotfiles.toml" ]]; then
    if _dot_toml_get "$DOTFILES/dotfiles.toml" git signingkey > /dev/null 2>&1 \
      || grep -qE '^\[' "$DOTFILES/dotfiles.toml"; then
      _check "dotfiles.toml" true
    else
      _check "dotfiles.toml" warn "no recognizable [section] headers"
    fi
  else
    _check "dotfiles.toml" warn "not present (optional)"
  fi

  echo ""
  if ((rc == 0)); then
    echo "All checks passed."
  else
    echo "One or more checks failed."
  fi
  unfunction _check 2> /dev/null
  return "$rc"
}

_dot_update() {
  local DOTFILES="${1:-${DOTFILES:-$HOME/Projects/dotfiles}}"
  local _c='\033[0;36m' _g='\033[0;32m' _r='\033[0;31m' _n='\033[0m'

  echo -e "${_c}->${_n} Pulling latest from origin..."
  (cd "$DOTFILES" && git pull --rebase --autostash) || {
    echo -e "${_r}x${_n} Pull failed. Resolve conflicts then retry." >&2
    return 1
  }

  if command -v stow &> /dev/null && [[ -d "$DOTFILES/stow" ]]; then
    echo -e "${_c}->${_n} Re-applying stow links..."
    (cd "$DOTFILES" && stow --dir="$DOTFILES/stow" --target="$HOME" \
      --restow $(ls stow) 2> /dev/null) \
      || echo -e "${_r}x${_n} Stow failed; run install.sh manually." >&2
  fi

  if [[ -x "$DOTFILES/install.sh" ]]; then
    echo -e "${_c}->${_n} Installer dry-run (re-run without --dry-run to apply):"
    (cd "$DOTFILES" && bash install.sh --dry-run) || true
  fi

  echo -e "${_g}v${_n} Update complete."
}
