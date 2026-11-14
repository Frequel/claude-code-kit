#!/usr/bin/env bash
# UserPromptSubmit: remind the model, on every real prompt, to apply rules/delegation.md.
#
# Rules are text the model may forget deep into a long session; a hook is run by the harness on
# every prompt, so the "is this trivial, or does it split into agents?" check never depends on the
# user asking for it. The reminder is deliberately short (about 80 tokens) and is skipped for:
#   - slash commands (they carry their own workflow),
#   - very short prompts (answers like "yes", "ok", "go on"),
#   - sessions that set CLAUDE_KIT_DELEGATION_CHECK=0.
# Unlike the other hooks this one is not silent on the happy path: its stdout is the point.
set -uo pipefail

input=$(cat 2>/dev/null || true) # always drain stdin, even when switched off
[ "${CLAUDE_KIT_DELEGATION_CHECK:-1}" = "0" ] && exit 0
prompt=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("prompt") or "").strip())
except Exception: print("")' 2>/dev/null)

case "$prompt" in
  /*) exit 0 ;;
esac
[ "${#prompt}" -lt "${CLAUDE_KIT_DELEGATION_MIN_CHARS:-40}" ] && exit 0

cat <<'EOF'
Delegation check (rules/delegation.md, standing request: no need to be asked): classify this task first.
Trivial (one step, clear, easy to undo) -> do it inline, no plan. Not trivial (dependent steps, more than 2-3 files, a choice
between approaches, hard-to-undo live state, unclear scope) -> plan mode with a who-does-what table. Then delegate only what
pays: independent parts in parallel, mechanical bulk to Haiku, specified implementation to the stack's *-service-dev (Sonnet),
checks to gate-runner (Haiku), review to staff-reviewer (Opus). Say in one line what you decided and why.
EOF
exit 0
