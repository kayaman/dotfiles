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
  GIT_SIGNINGKEY_GPG="$TMP/gpg-two" "$SCRIPT" 2> /dev/null)"
check "newest key chosen" "BBBB000000000002" "$out"

echo "[zero matching keys -> non-zero exit]"
make_gpg "$TMP/gpg-none"
if GIT_SIGNINGKEY_TOML="$TMP/empty.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG="$TMP/gpg-none" "$SCRIPT" > /dev/null 2>&1; then
  zrc=ok
else
  zrc=fail
fi
check "zero keys exits non-zero" "fail" "$zrc"

echo "[--write produces a parseable include file]"
make_gpg "$TMP/gpg-one2" "$ONE"
GIT_SIGNINGKEY_TOML="$TMP/empty.toml" GIT_SIGNINGKEY_EMAIL=x@y.z \
  GIT_SIGNINGKEY_GPG="$TMP/gpg-one2" GIT_LOCAL_CONFIG="$TMP/local.gitconfig" \
  "$SCRIPT" --write > /dev/null 2>&1
out="$(git config --file "$TMP/local.gitconfig" user.signingkey)"
check "written file parses" "AAAA000000000001" "$out"

echo ""
echo "passed: $pass  failed: $fail"
[[ "$fail" -eq 0 ]]
