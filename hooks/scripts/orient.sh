#!/usr/bin/env bash
# SessionStart: one compact orientation block — repo, branch and stack.
# Stays silent outside the projects directory (default ~/projects, override with
# CLAUDE_KIT_PROJECTS_DIR). A layer adds its own lines with its own SessionStart hook.
set -uo pipefail

input=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd","") or "")
except Exception: print("")' 2>/dev/null)
cwd="${cwd:-$PWD}"

case "$cwd" in
  "${CLAUDE_KIT_PROJECTS_DIR:-$HOME/projects}"*) : ;;
  *) exit 0 ;;
esac

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
repo=$(basename "$root")
branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

# Manifests may sit one or two levels down (workspaces, multi-crate repos).
has() { find "$root" -maxdepth 3 -name "$1" -not -path "*/node_modules/*" -not -path "*/.venv/*" -print -quit 2>/dev/null | grep -q .; }
stack=""
has Cargo.toml && stack="$stack rust"
has go.mod && stack="$stack go"
{ has pyproject.toml || has requirements.txt || has manage.py; } && stack="$stack python"
has package.json && stack="$stack typescript"
{ compgen -G "$root/*pipelines.yml" >/dev/null || [ -d "$root/.github/workflows" ] || [ -f "$root/.gitlab-ci.yml" ]; } && stack="$stack ci-pipeline"
[ -d "$root/.tokensave" ] && stack="$stack tokensave-indexed"

printf '## Repo orientation\n%s — branch `%s` —%s\n' "$repo" "$branch" "${stack:- unknown stack}"
[ -f "$root/CLAUDE.md" ] || printf 'No CLAUDE.md in this repo: build one from the kit template before non-trivial work.\n'
exit 0
