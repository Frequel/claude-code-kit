#!/usr/bin/env bash
# PreToolUse(Bash): refuse `git commit` / `git push` on a protected branch (master, main, develop),
# pushes whose refspec targets one, and force-pushes (-f, --force, +refspec; --force-with-lease is
# allowed). The command is parsed, not grepped: text inside quotes, heredocs and echo arguments is
# ignored, and the branch checked is the one of the repository the command acts on (after `cd` and
# `git -C`), not of the session directory. Deny is returned as JSON so the reason reaches Claude;
# everything else passes through silently. A missing python3 allows; a parser crash on a command that
# mentions `git commit|push` denies (fail closed, the only hook that does).
set -uo pipefail

command -v python3 >/dev/null 2>&1 || exit 0
lib="$(dirname "${BASH_SOURCE[0]}")/lib/cmdparse.py"
input=$(cat)
out=$(printf '%s' "$input" | python3 -I "$lib" guard 2>/dev/null) || out=""
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
