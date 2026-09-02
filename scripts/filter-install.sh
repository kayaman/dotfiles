#!/usr/bin/env bash
# Register the dot-secrets git clean filter for this clone. Lines matching ERE
# patterns in .dotfilter are redacted in the git index only — working-tree
# files are never touched. Idempotent; safe to re-run. Called by install.sh
# and by `dot filter-install` (stow/zsh/.functions).

set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOTFILTER="$DOTFILES/.dotfilter"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ ! -d "$DOTFILES/.git" ]]; then
  echo "Error: $DOTFILES is not a git repository." >&2
  exit 1
fi

if [[ ! -f "$DOTFILTER" ]]; then
  echo -e "${YELLOW}No .dotfilter found.${NC} Create one: dot filter-add <pattern>"
  exit 1
fi

filter_script="$DOTFILES/.git/hooks/dot-clean-filter"
printf "%s\n" \
  '#!/usr/bin/env bash' \
  'DOTFILES="$(git rev-parse --show-toplevel 2>/dev/null)"' \
  'DOTFILTER="$DOTFILES/.dotfilter"' \
  '[[ ! -f "$DOTFILTER" ]] && { cat; exit 0; }' \
  'sed_expr=""' \
  'while IFS= read -r pattern; do' \
  '    [[ -z "$pattern" || "$pattern" == \#* ]] && continue' \
  '    pattern="${pattern//\//\\/}"' \
  '    pattern="${pattern//|/\\|}"' \
  '    sed_expr="${sed_expr}s|${pattern}|# [REDACTED by dot-filter]|Ig;"' \
  'done < "$DOTFILTER"' \
  '[[ -z "$sed_expr" ]] && { cat; exit 0; }' \
  'exec sed -E "$sed_expr"' \
  > "$filter_script"
chmod +x "$filter_script"

git -C "$DOTFILES" config filter.dot-secrets.clean "$filter_script"
git -C "$DOTFILES" config filter.dot-secrets.smudge "cat"
git -C "$DOTFILES" config filter.dot-secrets.required false

gitattributes="$DOTFILES/.gitattributes"
if ! grep -q "dot-secrets" "$gitattributes" 2> /dev/null; then
  echo "* filter=dot-secrets" >> "$gitattributes"
  echo -e "  ${GREEN}v${NC} filter=dot-secrets added to .gitattributes"
fi
echo -e "  ${GREEN}v${NC} Filter installed. Secrets stripped at git-add time."
