# Machine-local GPG Signing Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `user.signingkey` out of the tracked, stowed `~/.gitconfig` into an auto-generated, untracked git `include` file so the dotfiles repo stays byte-identical across machines and signing never breaks on sync.

**Architecture:** Tracked `.gitconfig` declares `[include] path = ~/.config/git/local.gitconfig`. A shared bash resolver (`scripts/git-signingkey.sh`) resolves the key (pin in `dotfiles.toml`, else newest GPG secret key for the identity email) and writes that include file. `install.sh`, `dot gpg-sync`, and the redirected `setup-git.sh` all funnel through it; nothing writes `git config --global`. The global lefthook is removed.

**Tech Stack:** bash, zsh, GNU stow, git, gpg, python3 `tomllib`. No bats — verification is shellcheck + shfmt + `bash -n`/`zsh -n` (matching `.github/workflows/shell-lint.yml`) plus a stubbed-`gpg` test script run directly.

**Testing note:** `scripts/git-signingkey.sh` takes four env overrides purely so the test can run hermetically: `GIT_SIGNINGKEY_GPG` (path to gpg binary), `GIT_SIGNINGKEY_TOML` (pin source), `GIT_SIGNINGKEY_EMAIL` (identity email), `GIT_LOCAL_CONFIG` (output file). Production paths leave them unset.

**Signing continuity:** Task 1 restores the tracked key (`34940358712F23FE`) so commits sign normally from Task 1 onward. Task 3 writes the include file *before* Task 4 removes the key from the tracked file, so signing never lapses. Commits in this plan are normally signed — no `--no-gpg-sign`.

---

### Task 1: Discard obsolete staged changes (unbreak signing)

The working tree + index hold a stale revert of `.gitconfig` (`signingkey` → `8237E64F98A71AD8`, which is **not in this machine's keyring**) and a rewritten lefthook path. Reset both to HEAD; the committed `.gitconfig` already has the correct key `34940358712F23FE`, which restores working signing immediately.

**Files:**
- Modify (restore): `stow/git/.gitconfig`, `stow/git/.githooks/pre-commit`

- [ ] **Step 1: Confirm the staged state**

Run: `git status -s stow/git/`
Expected: `M  stow/git/.gitconfig` and `M  stow/git/.githooks/pre-commit`

- [ ] **Step 2: Restore both files to HEAD**

```bash
git restore --staged --worktree stow/git/.gitconfig stow/git/.githooks/pre-commit
```

- [ ] **Step 3: Verify the good key is back and signing works**

Run:
```bash
grep signingkey stow/git/.gitconfig
git config user.signingkey
gpg --list-secret-keys "$(git config user.signingkey)" >/dev/null && echo "KEY OK"
```
Expected: `signingkey = 34940358712F23FE`, same id from `git config`, and `KEY OK`.

- [ ] **Step 4: No commit**

Nothing to commit — this only discards uncommitted changes. Proceed to Task 2.

---

### Task 2: Create the shared resolver `scripts/git-signingkey.sh`

**Files:**
- Create: `scripts/git-signingkey.sh`
- Test: `tests/git-signingkey.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/git-signingkey.test.sh`:

```bash
#!/usr/bin/env bash
# Hermetic unit tests for scripts/git-signingkey.sh using a stubbed gpg.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/git-signingkey.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "  ok: $1"
    pass=$((pass + 1))
  else
    echo "  FAIL: $1 (want '$2' got '$3')"
    fail=$((fail + 1))
  fi
}

# make_gpg <file> <colon-line>...  — stub that ignores args and prints records.
make_gpg() {
  local f="$1"
  shift
  {
    echo '#!/usr/bin/env bash'
    echo 'cat <<EOF'
    printf '%s\n' "$@"
    echo 'EOF'
  } > "$f"
  chmod +x "$f"
}

# sec record fields: 1=sec 5=keyid(long) 6=creation-epoch
ONE="sec:-:255:22:AAAA000000000001:1700000000:::-:::scaESCA:::+::ed25519::"
TWO_OLD="sec:-:255:22:AAAA000000000001:1700000000:::-:::scaESCA:::+::ed25519::"
TWO_NEW="sec:-:255:22:BBBB000000000002:1800000000:::-:::scaESCA:::+::ed25519::"

echo "[pin override wins, gpg never consulted]"
printf '[git]\nsigningkey = "DEADBEEFCAFE0001"\n' > "$TMP/pin.toml"
out="$(GIT_SIGNINGKEY_TOML="$TMP/pin.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG=/bin/false "$SCRIPT")"
check "pin used verbatim" "DEADBEEFCAFE0001" "$out"

echo "[single matching key]"
make_gpg "$TMP/gpg-one" "$ONE"
printf '[git]\nsigningkey = ""\n' > "$TMP/empty.toml"
out="$(GIT_SIGNINGKEY_TOML="$TMP/empty.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG="$TMP/gpg-one" "$SCRIPT")"
check "single key resolved" "AAAA000000000001" "$out"

echo "[multiple keys -> newest by creation epoch]"
make_gpg "$TMP/gpg-two" "$TWO_OLD" "$TWO_NEW"
out="$(GIT_SIGNINGKEY_TOML="$TMP/empty.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG="$TMP/gpg-two" "$SCRIPT" 2>/dev/null)"
check "newest key chosen" "BBBB000000000002" "$out"

echo "[zero matching keys -> non-zero exit]"
make_gpg "$TMP/gpg-none"
GIT_SIGNINGKEY_TOML="$TMP/empty.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG="$TMP/gpg-none" "$SCRIPT" >/dev/null 2>&1
check "zero keys exits non-zero" "fail" "$([[ $? -ne 0 ]] && echo fail || echo ok)"

echo "[--write produces a parseable include file]"
make_gpg "$TMP/gpg-one2" "$ONE"
GIT_SIGNINGKEY_TOML="$TMP/empty.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG="$TMP/gpg-one2" GIT_LOCAL_CONFIG="$TMP/local.gitconfig" \
  "$SCRIPT" --write >/dev/null 2>&1
out="$(git config --file "$TMP/local.gitconfig" user.signingkey)"
check "written file parses" "AAAA000000000001" "$out"

echo ""
echo "passed: $pass  failed: $fail"
[[ "$fail" -eq 0 ]]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/git-signingkey.test.sh`
Expected: FAIL — `scripts/git-signingkey.sh` does not exist yet (errors / non-zero exit).

- [ ] **Step 3: Write the resolver**

Create `scripts/git-signingkey.sh`:

```bash
#!/usr/bin/env bash
# git-signingkey.sh — resolve this machine's GPG signing key and optionally
# write it to the machine-local git include file.
#
#   git-signingkey.sh            print the resolved long key id to stdout
#   git-signingkey.sh --write    also write the include file
#
# Resolution order:
#   1. dotfiles.toml [git] signingkey, if non-empty (explicit pin)
#   2. newest secret key whose uid matches the git identity email
# Exits non-zero with a stderr diagnostic when no key can be resolved.
#
# Test hooks (unset in normal use):
#   GIT_SIGNINGKEY_GPG    path to the gpg binary
#   GIT_SIGNINGKEY_TOML   path to the pin source (dotfiles.toml)
#   GIT_SIGNINGKEY_EMAIL  identity email override
#   GIT_LOCAL_CONFIG      output path for the include file

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOML="${GIT_SIGNINGKEY_TOML:-$REPO/dotfiles.toml}"
LOCAL_GITCONFIG="${GIT_LOCAL_CONFIG:-$HOME/.config/git/local.gitconfig}"
GPG="${GIT_SIGNINGKEY_GPG:-$(command -v gpg2 || command -v gpg || true)}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'
warn() { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
err() { echo -e "${RED}[ERR]${NC}   $*" >&2; }
ok() { echo -e "${GREEN}[OK]${NC}    $*" >&2; }

# read_toml_git <key> — print dotfiles.toml [git] <key>, or nothing.
read_toml_git() {
  [[ -f "$TOML" ]] || return 0
  python3 -c '
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
    v = data.get("git", {}).get(sys.argv[1], "")
    if isinstance(v, str) and v.strip():
        sys.stdout.write(v.strip())
except Exception:
    pass
' "$1" < "$TOML" 2> /dev/null || true
}

identity_email() {
  [[ -n "${GIT_SIGNINGKEY_EMAIL:-}" ]] && {
    printf '%s' "$GIT_SIGNINGKEY_EMAIL"
    return
  }
  local e
  e="$(git config user.email 2> /dev/null || true)"
  [[ -n "$e" ]] && {
    printf '%s' "$e"
    return
  }
  read_toml_git email
}

count_keys() { "$GPG" --list-secret-keys --with-colons "$1" 2> /dev/null | awk -F: '$1=="sec"' | wc -l; }

newest_key() {
  "$GPG" --list-secret-keys --with-colons "$1" 2> /dev/null \
    | awk -F: '$1=="sec"{print $6, $5}' | sort -rn | head -1 | awk '{print $2}'
}

resolve() {
  local pin email key n
  pin="$(read_toml_git signingkey)"
  if [[ -n "$pin" ]]; then
    printf '%s' "$pin"
    return 0
  fi
  email="$(identity_email)"
  [[ -n "$email" ]] || {
    err "no git identity email; set user.email or dotfiles.toml [git] email"
    return 2
  }
  [[ -n "$GPG" && -x "$GPG" ]] || {
    err "gpg not available; pin a key via dotfiles.toml [git] signingkey"
    return 3
  }
  n="$(count_keys "$email")"
  if [[ "$n" -eq 0 ]]; then
    err "no gpg secret key matches $email; pin via dotfiles.toml [git] signingkey"
    return 4
  fi
  key="$(newest_key "$email")"
  [[ "$n" -gt 1 ]] && warn "multiple ($n) gpg keys match $email; using newest $key — pin via dotfiles.toml [git] signingkey to override"
  printf '%s' "$key"
}

write_local() {
  local key="$1"
  mkdir -p "$(dirname "$LOCAL_GITCONFIG")"
  printf '%s\n' \
    "# Generated by dotfiles — machine-local, do not edit by hand." \
    "# Regenerate: dot gpg-sync   (or re-run install.sh)" \
    "[user]" \
    "	signingkey = $key" \
    > "$LOCAL_GITCONFIG"
}

main() {
  local do_write=0
  [[ "${1:-}" == "--write" ]] && do_write=1
  local key
  if ! key="$(resolve)"; then exit $?; fi
  if [[ "$do_write" -eq 1 ]]; then
    write_local "$key"
    ok "Wrote $LOCAL_GITCONFIG (signingkey = $key)"
  else
    printf '%s\n' "$key"
  fi
}

main "$@"
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run:
```bash
chmod +x scripts/git-signingkey.sh
bash tests/git-signingkey.test.sh
```
Expected: all five `ok:` lines, `passed: 5  failed: 0`, exit 0.

- [ ] **Step 5: Lint**

Run: `shellcheck -e SC1091 scripts/git-signingkey.sh tests/git-signingkey.test.sh && shfmt -i 2 -ci -bn -sr -d scripts/git-signingkey.sh tests/git-signingkey.test.sh`
Expected: no output (clean). Fix any reported issues, then re-run Step 4.

- [ ] **Step 6: Commit**

```bash
git add scripts/git-signingkey.sh tests/git-signingkey.test.sh
git commit -m "feat: add git-signingkey resolver (pin-else-newest)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Generate the machine-local include file

Run the resolver against the real keyring so `~/.config/git/local.gitconfig` exists *before* the key is removed from the tracked file.

**Files:**
- Create (runtime, untracked): `~/.config/git/local.gitconfig`

- [ ] **Step 1: Generate it**

Run: `scripts/git-signingkey.sh --write`
Expected: `[OK]    Wrote /home/kayaman/.config/git/local.gitconfig (signingkey = 34940358712F23FE)` (a warning about two matching keys is expected and fine — newest wins).

- [ ] **Step 2: Verify content and that it is outside the repo**

Run:
```bash
cat ~/.config/git/local.gitconfig
git config --file ~/.config/git/local.gitconfig user.signingkey
git -C "$DOTFILES" check-ignore -v ~/.config/git/local.gitconfig 2>/dev/null || echo "outside repo (untracked) — good"
```
Expected: file shows `signingkey = 34940358712F23FE`; the path is outside the repo tree, so it can never be tracked.

- [ ] **Step 3: No commit** — this is a generated machine-local file.

---

### Task 4: Rewire the tracked `.gitconfig`

Drop the key, drop the global `hooksPath`, add the include. After this, signing comes from the include file written in Task 3.

**Files:**
- Modify: `stow/git/.gitconfig`

- [ ] **Step 1: Remove the `hooksPath` line from `[core]`**

In `stow/git/.gitconfig`, delete this line:

```
    hooksPath = ~/.githooks
```

- [ ] **Step 2: Remove the `signingkey` line and add the include**

Replace the trailing `[user]` block:

```
[user]
	name = Marco Antonio Gonzalez Junior
	email = m@rco.sh
	signingkey = 34940358712F23FE
```

with:

```
[user]
	name = Marco Antonio Gonzalez Junior
	email = m@rco.sh

# Machine-local overrides (signingkey, etc.) — untracked, generated by
# scripts/git-signingkey.sh. A missing file is silently ignored by git.
[include]
	path = ~/.config/git/local.gitconfig
```

- [ ] **Step 3: Verify the merged key still resolves through the include**

Run:
```bash
git config user.signingkey
git config --get core.hooksPath || echo "hooksPath removed — good"
```
Expected: `34940358712F23FE` (now sourced from the include); `hooksPath removed — good`.

- [ ] **Step 4: Lint and prove a signed commit works end-to-end**

Run:
```bash
shfmt -d stow/git/.gitconfig 2>/dev/null || true   # gitconfig is not shell; ignore
git add stow/git/.gitconfig
git commit -m "refactor(git): source signingkey from machine-local include

Move user.signingkey out of the tracked config into an untracked
~/.config/git/local.gitconfig include, and drop the global hooksPath.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git log --show-signature -1 | grep -i "Good signature" && echo "SIGNED OK"
```
Expected: commit succeeds and `SIGNED OK` prints — signing now flows through the include file, proving the new path works.

---

### Task 5: Remove the global lefthook

**Files:**
- Delete: `stow/git/.githooks/` (and its `pre-commit`)
- Runtime: remove stale `~/.githooks` stow symlink

- [ ] **Step 1: Remove the tracked hook directory**

Run: `git rm -r stow/git/.githooks`
Expected: `rm 'stow/git/.githooks/pre-commit'`.

- [ ] **Step 2: Remove the stale stow symlink and re-stow git**

Run:
```bash
[[ -L "$HOME/.githooks" ]] && rm -f "$HOME/.githooks"
stow -D -t "$HOME" -d "$DOTFILES/stow" git && stow -R -t "$HOME" -d "$DOTFILES/stow" git
```
Expected: no errors; `~/.githooks` no longer exists.

- [ ] **Step 3: Verify no global hooks remain**

Run: `git config --get core.hooksPath; ls -la ~/.githooks 2>&1 | head -1`
Expected: empty `core.hooksPath`; `~/.githooks` reported missing.

- [ ] **Step 4: Update the CI exclusion comments (optional cleanup)**

`.github/workflows/shell-lint.yml` references `stow/git/.githooks/` in three exclusion comments/globs. The `grep -vE '^(stow/git/\.githooks/|...)'` and `ignore_paths` entries are now no-ops but harmless. Leave the patterns (defensive) but no change is required. Skip if no edit desired.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(git): remove global lefthook (machine-path churn source)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Wire generation into `install.sh`

**Files:**
- Modify: `install.sh` (new `setup_git_signingkey` function + `main` call)

- [ ] **Step 1: Add the function**

Insert after the `symlink_dotfiles` function definition (before section 5 / Oh My Zsh):

```bash
# ── 4b. Machine-local git signing key ────────────────────────
# Resolve this machine's GPG key (pin in dotfiles.toml, else newest secret
# key for the identity email) and write ~/.config/git/local.gitconfig, which
# the tracked .gitconfig pulls in via [include]. Never fails the install.
setup_git_signingkey() {
  section "Git Signing Key (machine-local)"
  local gen="$DOTFILES/scripts/git-signingkey.sh"
  if [[ ! -x "$gen" ]]; then
    warn "scripts/git-signingkey.sh missing — skipping signing key setup"
    return 0
  fi
  if "$gen" --write; then
    ok "Wrote machine-local signing key to ~/.config/git/local.gitconfig"
  else
    warn "No GPG signing key resolved — set dotfiles.toml [git] signingkey or import your key, then run: dot gpg-sync"
  fi
}
```

- [ ] **Step 2: Call it from `main` after stow**

In `main`, immediately after `run_step symlink_dotfiles`, add:

```bash
  run_step setup_git_signingkey
```

- [ ] **Step 3: Lint and syntax-check**

Run: `bash -n install.sh && shellcheck -e SC1091 install.sh && shfmt -i 2 -ci -bn -sr -d install.sh`
Expected: clean (no output).

- [ ] **Step 4: Dry-run shows the step**

Run: `bash install.sh --dry-run 2>&1 | grep -i "setup_git_signingkey"`
Expected: a `[DRY] Would run: setup_git_signingkey` line.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat(install): generate machine-local signing key after stow

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Add `dot gpg-sync`, update hook in `dot`

**Files:**
- Modify: `stow/zsh/functions.d/dot.zsh` (new subcommand, help line, `_dot_update` call, `_dot_doctor` check)

- [ ] **Step 1: Add the `gpg-sync` case**

In the `case "$cmd"` block (e.g. after the `update)` case at line ~213), add:

```zsh
    gpg-sync)
      if [[ -x "$DOTFILES/scripts/git-signingkey.sh" ]]; then
        "$DOTFILES/scripts/git-signingkey.sh" --write \
          && echo -e "$_ok Signing key synced." \
          || {
            echo -e "$_err Could not resolve a signing key." >&2
            echo -e "$_info Pin one: set [git] signingkey in dotfiles.toml" >&2
            return 1
          }
      else
        echo -e "$_err scripts/git-signingkey.sh not found." >&2
        return 1
      fi
      ;;
```

- [ ] **Step 2: Add a help line**

In the `help` case `printf` list (near line 84, after the `"update"` row), add:

```zsh
        "gpg-sync" "Regenerate ~/.config/git/local.gitconfig from your GPG key" \
```

- [ ] **Step 3: Call it from `_dot_update`**

In `_dot_update`, after the stow re-apply block and before the installer dry-run, add:

```zsh
  if [[ -x "$DOTFILES/scripts/git-signingkey.sh" ]]; then
    echo -e "${_c}->${_n} Syncing GPG signing key..."
    "$DOTFILES/scripts/git-signingkey.sh" --write > /dev/null 2>&1 \
      && echo -e "${_g}v${_n} Signing key synced." \
      || echo -e "${_r}x${_n} Signing key unresolved; run: dot gpg-sync"
  fi
```

- [ ] **Step 4: Replace doctor check #5**

In `_dot_doctor`, replace the entire check #5 block (the `# 5. dotfiles.toml parses (if present).` comment and its `if/elif/else` through the closing `fi`) with:

```zsh
  # 5. GPG signing key resolves and is present in the local keyring.
  local sk
  sk=$(git config user.signingkey 2> /dev/null)
  if [[ -z "$sk" ]]; then
    _check "git signing key" warn "user.signingkey unset — run: dot gpg-sync"
  elif command -v gpg > /dev/null 2>&1 && gpg --list-secret-keys "$sk" > /dev/null 2>&1; then
    _check "git signing key ($sk)" true
  else
    _check "git signing key" warn "$sk not in keyring — run: dot gpg-sync"
  fi
```

- [ ] **Step 5: Syntax-check (zsh) and smoke-test**

Run:
```bash
zsh -n stow/zsh/functions.d/dot.zsh && echo "ZSH SYNTAX OK"
zsh -ic 'source stow/zsh/functions.d/dot.zsh; dot gpg-sync'
zsh -ic 'source stow/zsh/functions.d/dot.zsh; dot doctor' | grep -i "signing key"
```
Expected: `ZSH SYNTAX OK`; `gpg-sync` prints `Signing key synced.`; doctor prints a `PASS` line `git signing key (34940358712F23FE)`.

- [ ] **Step 6: Commit**

```bash
git add stow/zsh/functions.d/dot.zsh
git commit -m "feat(dot): add gpg-sync, sync key on update, doctor key check

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Redirect `scripts/setup-git.sh` away from `--global`

So the interactive path also writes the untracked include file instead of mutating the stowed symlink.

**Files:**
- Modify: `scripts/setup-git.sh`

- [ ] **Step 1: Add the local-config target near the top**

After the color/helper definitions (after line 14, before the banner), add:

```bash
LOCAL_GITCONFIG="$HOME/.config/git/local.gitconfig"
mkdir -p "$(dirname "$LOCAL_GITCONFIG")"
gc() { git config --file "$LOCAL_GITCONFIG" "$@"; }
```

- [ ] **Step 2: Redirect the name/email reads and writes**

Change the four `git config --global user.name`/`user.email` *reads* (lines 68, 83) from `--global` to merged reads, and the *writes* (lines 72, 75, 87, 90) to `gc`:

- Line 68: `current_name=$(git config user.name || echo "$toml_name")`
- Line 72: `gc user.name "$new_name"`
- Line 75: `gc user.name "$current_name"`
- Line 83: `current_email=$(git config user.email || echo "$toml_email")`
- Line 87: `gc user.email "$new_email"`
- Line 90: `gc user.email "$current_email"`

- [ ] **Step 3: Redirect the GPG block writes**

In section 3, change the read (line 110) and all `git config --global` writes (lines 115–117 and 121–123) to merged read + `gc`:

- Line 110: `current_signingkey=$(git config user.signingkey || echo "$toml_signingkey")`
- Lines 115–117:
  ```bash
  gc user.signingkey "$new_keyid"
  gc commit.gpgsign true
  gc tag.gpgSign true
  ```
- Lines 121–123:
  ```bash
  gc user.signingkey "$current_signingkey"
  gc commit.gpgsign true
  gc tag.gpgSign true
  ```

- [ ] **Step 4: Fix the final summary read**

Line 133 lists `git config --global -l`. Change to the merged view so it reflects the include:

```bash
git config -l | grep -E '^user\.|^commit\.gpgsign|^tag\.gpgsign'
```

- [ ] **Step 5: Lint and syntax-check**

Run: `bash -n scripts/setup-git.sh && shellcheck -e SC1091 scripts/setup-git.sh && shfmt -i 2 -ci -bn -sr -d scripts/setup-git.sh`
Expected: clean.

- [ ] **Step 6: Verify it no longer dirties the tracked config**

Run (non-interactively, accepting defaults, declining GPG):
```bash
printf '\n\nN\n' | bash scripts/setup-git.sh >/dev/null 2>&1 || true
git status -s stow/git/.gitconfig
```
Expected: **no output** from `git status` — the tracked `.gitconfig` is untouched; any writes landed in `~/.config/git/local.gitconfig`.

- [ ] **Step 7: Commit**

```bash
git add scripts/setup-git.sh
git commit -m "fix(setup-git): write to machine-local include, never --global

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Retire the `.dotfilter` signingkey pattern and clarify the toml example

**Files:**
- Modify: `.dotfilter`, `dotfiles.toml.example`

- [ ] **Step 1: Remove the redaction pattern**

In `.dotfilter`, delete the line:

```
signingkey\s*=.*
```

(Leave every token/secret pattern intact — those still belong in the repo's index-redaction net.)

- [ ] **Step 2: Clarify the pin semantics in the example**

In `dotfiles.toml.example`, change the `[git]` `signingkey` comment from:

```
signingkey = ""                      # GPG key fingerprint; leave blank to disable commit signing
```

to:

```
signingkey = ""                      # Optional pin. Blank = auto-detect newest GPG secret key for this email.
```

- [ ] **Step 3: Verify the key is no longer redaction-matched anywhere tracked**

Run: `git grep -nE 'signingkey' -- ':!docs/' ':!.dotfilter'`
Expected: no hits in `stow/git/.gitconfig` (the key line is gone); only `scripts/` references (which write to the include file, not the tracked config) remain.

- [ ] **Step 4: Commit**

```bash
git add .dotfilter dotfiles.toml.example
git commit -m "chore: drop signingkey redaction; clarify dotfiles.toml pin

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Re-run the unit test**

Run: `bash tests/git-signingkey.test.sh`
Expected: `passed: 5  failed: 0`.

- [ ] **Step 2: Run the CI lint/syntax suite locally**

Run:
```bash
shfmt -i 2 -ci -bn -sr -d $(shfmt -f . | grep -vE '^(stow/git/\.githooks/|stow/zsh/)')
shellcheck -e SC1091 $(shfmt -f . | grep -vE '^(stow/git/\.githooks/|stow/zsh/)')
bash -n install.sh bootstrap.sh; for s in scripts/*.sh; do bash -n "$s"; done
for f in stow/zsh/.zshrc stow/zsh/functions.d/*.zsh; do zsh -n "$f"; done
```
Expected: all clean / no errors. (`stow/git/.githooks/` no longer exists, so its exclusion is moot.)

- [ ] **Step 3: `dot doctor` is green**

Run: `zsh -ic 'source stow/zsh/functions.d/dot.zsh; dot doctor'`
Expected: stow-links PASS, required-tools PASS, `git signing key (34940358712F23FE)` PASS.

- [ ] **Step 4: Confirm the repo is clean and signed**

Run: `git status -s && git log --show-signature -3 | grep -i "good signature" | head -1`
Expected: clean working tree (no `stow/git/.gitconfig` churn), and recent commits show a good signature.

- [ ] **Step 5: Cross-machine simulation (the real acceptance test)**

Simulate a fresh checkout where the include file is absent, then regenerate:
```bash
mv ~/.config/git/local.gitconfig /tmp/local.bak
git config user.signingkey || echo "no key (expected on fresh machine)"
scripts/git-signingkey.sh --write
git config user.signingkey
```
Expected: with the include gone, `user.signingkey` is empty (git silently ignores the missing include — no error, no churn); after `--write` it resolves to `34940358712F23FE` again. This is exactly the new-machine flow.

---

## Self-Review

**Spec coverage:**
- Tracked `.gitconfig` include + key removal → Task 4. ✓
- Untracked `~/.config/git/local.gitconfig` → Tasks 3, 4. ✓
- Shared resolver, pin-else-newest, `--write` → Task 2. ✓
- `install.sh` wiring → Task 6. ✓
- `dot gpg-sync` + `_dot_update` + doctor check → Task 7. ✓
- `setup-git.sh` redirect (no `--global`) → Task 8. ✓
- `.dotfilter` pattern removal + toml example → Task 9. ✓
- Remove global hook entirely (`hooksPath` + `.githooks/`) → Tasks 4, 5. ✓
- Error-handling matrix (gpg missing, 0/2+ keys, pin, absent include) → resolver in Task 2 + acceptance test in Task 10 Step 5. ✓

**Placeholder scan:** No TBD/TODO; every code/edit step shows concrete content. ✓

**Type/name consistency:** `git-signingkey.sh` flag `--write`, env hooks `GIT_SIGNINGKEY_{GPG,TOML,EMAIL}` + `GIT_LOCAL_CONFIG`, include path `~/.config/git/local.gitconfig`, and `dot gpg-sync` are used identically across Tasks 2, 3, 6, 7, 8, 10. ✓
