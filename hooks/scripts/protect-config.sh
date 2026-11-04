#!/usr/bin/env bash
# PreToolUse(Bash|Edit|Write|MultiEdit): protect the Claude Code configuration itself.
#
# - Refuses commands that delete or move the kit, the Claude config dir (~/.claude or
#   $CLAUDE_CONFIG_DIR: commands, rules, agents, skills, hooks, settings, manifests, plugins,
#   projects/*/memory), the kit's top-level folders and layers, and any folder listed in a
#   `protected-paths` file (in the config dir or in a layer in use). Personal commands and rules
#   often exist nowhere else; broken links are fixed by rerunning install.sh, never by deleting
#   directories. Single files inside the kit are ordinary git-recoverable edits and are allowed.
# - Before any other change to the kit or to the configuration: takes a snapshot (at most one an
#   hour) and, once per session, reminds the user that these files are what Claude Code loads.
# The command is parsed (see lib/cmdparse.py), so quoted text and unrelated commands never match.
# Silent and exit 0 for everything else, and on any parse error.
#
# Test overrides: CLAUDE_CONFIG_DIR, CLAUDE_KIT_ROOT (default: derived from this script), TMPDIR.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${CLAUDE_KIT_ROOT:-$(cd "$here/../.." && pwd -P)}"
export CLAUDE_KIT_ROOT="$KIT_ROOT"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input=$(cat)
parsed=$(printf '%s' "$input" | python3 -I "$here/lib/cmdparse.py" protect 2>/dev/null) || exit 0
tool=$(sed -n 1p <<< "$parsed")
session=$(sed -n 2p <<< "$parsed")
verdict=$(sed -n 3p <<< "$parsed")
target=$(sed -n 4p <<< "$parsed")

case "$verdict" in
  deny)
    python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}))' \
      "Blocked by protect-config: this command deletes or moves Claude Code configuration (the kit repo, ~/.claude commands/rules/agents/skills/hooks/memories, or a folder declared in protected-paths). Those directories hold personal files that exist nowhere else. To fix broken links run ./install.sh --check then ./install.sh in the kit; if something must really go, tell the user and let them run it."
    exit 0 ;;
  write) ;;
  path) ;;   # Edit/Write/MultiEdit on a protected path (decided by cmdparse, same list as Bash)
  *) exit 0 ;;
esac
: "$tool" "$target"

bash "$KIT_ROOT/scripts/backup-config.sh" --if-older-than 60 --quiet >/dev/null 2>&1 || true

stampdir="${TMPDIR:-/tmp}/claude-protect-config"
mkdir -p "$stampdir" 2>/dev/null
stamp="$stampdir/${session:-nosession}"
if [ ! -e "$stamp" ]; then
  : > "$stamp"
  python3 -c 'import json,sys; print(json.dumps({"systemMessage": sys.argv[1]}))' \
    "Reminder: you are changing the Claude Code configuration (the kit or ~/.claude). Claude loads its commands, rules, agents, skills and memories from there: never delete these folders or the kit repo, even to fix broken links (rerun ./install.sh). A snapshot was taken in ~/projects/.claude-config-backups and C:\\Users\\<you>\\claude-config-backups."
fi
exit 0
