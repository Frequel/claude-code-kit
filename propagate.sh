#!/usr/bin/env bash
# Bring one repository onto the kit: remove the duplicated command/agent/skill copies it
# carries, keep anything genuinely its own, and offer a CLAUDE.md skeleton when there is none.
#
# Dry run by default. Nothing is deleted without --apply, and --apply always backs up first.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=0
NO_TEMPLATE=0
BACKUP_DIR="${TMPDIR:-/tmp}/claude-kit-propagate-$(date +%Y%m%d-%H%M%S)"
targets=()

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --no-template) NO_TEMPLATE=1 ;;
    -h|--help) echo "usage: propagate.sh [--apply] [--no-template] <repo-path> [<repo-path>...]"; exit 0 ;;
    *) targets+=("$arg") ;;
  esac
done
[ ${#targets[@]} -gt 0 ] || { echo "usage: propagate.sh [--apply] [--no-template] <repo-path>..." >&2; exit 2; }

kit_sums=$(mktemp); trap 'rm -f "$kit_sums"' EXIT
find "$KIT_ROOT/commands" "$KIT_ROOT/agents" -name '*.md' -exec md5sum {} + | cut -d' ' -f1 | sort -u > "$kit_sums"

act() { # echo in dry-run, execute with --apply
  if [ "$APPLY" -eq 1 ]; then "$@"; else echo "    would: $*"; fi
}

for repo in "${targets[@]}"; do
  repo="${repo%/}"
  [ -d "$repo/.git" ] || { echo "skip $repo (not a git repository)"; continue; }
  name=$(basename "$repo")
  echo "== $name"

  if [ -d "$repo/.claude" ] && [ "$APPLY" -eq 1 ]; then
    mkdir -p "$BACKUP_DIR/$name"; cp -r "$repo/.claude" "$BACKUP_DIR/$name/"
  fi

  # 1. Flat skill files never load — they are dead weight everywhere.
  for f in "$repo"/.claude/skills/*.md; do
    [ -e "$f" ] || continue
    echo "  inert skill (never loads): ${f#$repo/}"
    act rm -f "$f"
  done
  [ -d "$repo/.claude/skills" ] && [ -z "$(ls -A "$repo/.claude/skills" 2>/dev/null)" ] && act rmdir "$repo/.claude/skills"

  # 2. Commands and agents: remove only what the kit already provides, keep local inventions.
  for f in "$repo"/.claude/commands/*.md "$repo"/.claude/agents/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f"); kind=$(basename "$(dirname "$f")")
    if [ -e "$KIT_ROOT/$kind/$base" ]; then
      if grep -qxF "$(md5sum "$f" | cut -d' ' -f1)" "$kit_sums"; then
        echo "  identical to the kit: ${f#$repo/}"
      else
        echo "  older/forked copy of a kit file: ${f#$repo/}"
      fi
      act rm -f "$f"
    else
      echo "  KEEP (not in the kit — promote it there if it is worth sharing): ${f#$repo/}"
    fi
  done
  for d in commands agents; do
    [ -d "$repo/.claude/$d" ] && [ -z "$(ls -A "$repo/.claude/$d" 2>/dev/null)" ] && act rmdir "$repo/.claude/$d"
  done

  # 3. CLAUDE.md: never overwrite; offer a skeleton when missing.
  if [ ! -f "$repo/CLAUDE.md" ] && [ "$NO_TEMPLATE" -eq 0 ]; then
    stack=base
    find "$repo" -maxdepth 3 -name Cargo.toml -print -quit | grep -q . && stack=rust
    find "$repo" -maxdepth 3 -name go.mod -print -quit | grep -q . && stack=go
    find "$repo" -maxdepth 3 \( -name pyproject.toml -o -name requirements.txt -o -name manage.py \) -print -quit | grep -q . && stack=python
    find "$repo" -maxdepth 3 -name package.json -not -path '*/node_modules/*' -print -quit | grep -q . && stack=typescript
    { [ -d "$repo/k8s-setup" ] || [ -d "$repo/helm-charts" ] || [ -d "$repo/terraform" ]; } && stack=infra
    echo "  no CLAUDE.md — $stack template available"
    act cp "$KIT_ROOT/templates/CLAUDE.$stack.md" "$repo/CLAUDE.md"
    [ "$APPLY" -eq 1 ] && echo "    template copied — it is a skeleton: fill it in and RUN every command before leaving it"
  fi
done

[ "$APPLY" -eq 1 ] && echo "backup: $BACKUP_DIR" || echo "(dry run — nothing changed; re-run with --apply)"
