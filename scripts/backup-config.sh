#!/usr/bin/env bash
# Snapshot the Claude Code configuration: this kit's working tree (uncommitted files and .git
# included — the kit may have no remote) and the user-level ~/.claude configuration (rules,
# commands, agents, skills, settings, manifest, memories). Credentials, history and caches are
# never copied.
#
# Destinations: $CLAUDE_CONFIG_BACKUP_DIRS (colon-separated) if set, otherwise
#   $HOME/projects/.claude-config-backups  — bind-mounted, so reachable from host and dev containers
#   /mnt/c/Users/<windows user>/claude-config-backups — another disk, outside OneDrive (WSL host only)
# A backup kept only inside a container is lost on rebuild: that is how the 2026-09-30 one vanished.
#
# usage: backup-config.sh [--if-older-than <minutes>] [--quiet]
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KEEP=30
MIN_AGE=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --if-older-than) MIN_AGE="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" -eq 1 ] || echo "$@"; }

destinations() {
  if [ -n "${CLAUDE_CONFIG_BACKUP_DIRS:-}" ]; then
    tr ':' '\n' <<< "$CLAUDE_CONFIG_BACKUP_DIRS"
    return
  fi
  echo "$HOME/projects/.claude-config-backups"
  # The Windows profile of the WSL user: the only folder under C:\Users with a Desktop that is
  # not a system profile. Skipped when ambiguous or absent (dev containers have no /mnt/c).
  local users
  users=$(find /mnt/c/Users -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | grep -vE '/(Public|Default|Default User|All Users)$' \
    | while IFS= read -r d; do [ -d "$d/Desktop" ] && echo "$d"; done || true)
  [ -n "$users" ] && [ "$(wc -l <<< "$users")" -eq 1 ] && echo "$users/claude-config-backups"
  return 0
}

mapfile -t dests < <(destinations)
primary="${dests[0]}"
mkdir -p "$primary"

if [ "$MIN_AGE" -gt 0 ] && [ -n "$(find "$primary" -maxdepth 1 -name 'claude-config-*.tar.gz' -mmin -"$MIN_AGE" -print -quit 2>/dev/null)" ]; then
  exit 0   # a recent snapshot exists
fi

stamp=$(date +%Y%m%d-%H%M%S)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
name="claude-config-$stamp.tar.gz"

# ~/.claude: only configuration. Symlinks are stored as links; their targets are in the kit part.
conf_items=()
for p in CLAUDE.md settings.json .claude-kit-manifest .claude-kit-layers protected-paths commands rules agents skills; do
  [ -e "$CLAUDE_DIR/$p" ] || [ -L "$CLAUDE_DIR/$p" ] && conf_items+=("$p")
done
while IFS= read -r m; do conf_items+=("${m#"$CLAUDE_DIR"/}"); done \
  < <(find "$CLAUDE_DIR/projects" -mindepth 2 -maxdepth 2 -type d -name memory 2>/dev/null)

tar -C "$CLAUDE_DIR" --exclude='skills/synced' -czf "$work/dot-claude.tar.gz" "${conf_items[@]}"
tar -C "$(dirname "$KIT_ROOT")" -czf "$work/kit.tar.gz" "$(basename "$KIT_ROOT")"
git -C "$KIT_ROOT" bundle create "$work/kit.bundle" --all >/dev/null 2>&1 || true
{
  echo "created: $stamp"
  echo "host home: $HOME"
  echo "kit: $KIT_ROOT ($(git -C "$KIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git -C "$KIT_ROOT" rev-parse --short HEAD 2>/dev/null))"
  echo "kit uncommitted:"; git -C "$KIT_ROOT" status --short 2>/dev/null | sed 's/^/  /'
  echo "restore: tar xzf kit.tar.gz -C $(dirname "$KIT_ROOT")  &&  tar xzf dot-claude.tar.gz -C ~/.claude   (kit.tar.gz includes layers/)"
} > "$work/README.txt"
tar -C "$work" -czf "$work/$name" README.txt dot-claude.tar.gz kit.tar.gz $( [ -f "$work/kit.bundle" ] && echo kit.bundle )

for d in "${dests[@]}"; do
  [ -n "$d" ] || continue
  if mkdir -p "$d" 2>/dev/null && cp "$work/$name" "$d/"; then
    # keep the newest $KEEP snapshots
    find "$d" -maxdepth 1 -name 'claude-config-*.tar.gz' -printf '%f\n' | sort -r | tail -n +$((KEEP+1)) \
      | while IFS= read -r old; do rm -f -- "${d:?}/$old"; done
    say "backup: $d/$name"
  else
    say "backup: could not write to $d" >&2
  fi
done
