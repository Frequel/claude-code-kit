#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): format the file that was just written.
# Silent on success; never blocks. Missing formatters are not an error.
set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("file_path","") or "")
except Exception: print("")' 2>/dev/null)

[ -n "$file" ] && [ -f "$file" ] || exit 0

have() { command -v "$1" >/dev/null 2>&1; }
out=""
case "$file" in
  *.rs)
    have rustfmt && out=$(rustfmt --edition 2024 "$file" 2>&1) ;;
  *.go)
    have gofmt && out=$(gofmt -w "$file" 2>&1) ;;
  *.py)
    if have ruff; then out=$(ruff format -q "$file" 2>&1)
    elif have black; then out=$(black -q "$file" 2>&1); fi ;;
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.md)
    # Only when the project actually uses prettier; never impose it.
    d=$(dirname "$file")
    while [ "$d" != "/" ] && [ ! -f "$d/package.json" ]; do d=$(dirname "$d"); done
    if [ -f "$d/package.json" ] && grep -q '"prettier"' "$d/package.json" 2>/dev/null && have npx; then
      out=$(cd "$d" && npx --no-install prettier --write "$file" 2>&1)
    fi ;;
  *.sh)
    have shfmt && out=$(shfmt -w -i 2 -ci "$file" 2>&1) ;;
esac

# A formatter that fails usually means the file does not parse — say so, do not block.
if [ -n "${out:-}" ]; then
  printf 'formatter on %s: %s\n' "$(basename "$file")" "$(printf '%s' "$out" | head -3)"
fi
exit 0
