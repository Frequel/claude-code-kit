#!/usr/bin/env bash
# Tests for doctor.sh.
#
# Every case builds a throw-away world and runs a COPY of doctor.sh in it: a fake kit (a git repository
# holding copies of doctor.sh and scripts/backup-config.sh, with a bare repository as its "remote"), a fake
# HOME with a ~/.claude, and stub claude / tokensave / rtk executables first on PATH. The real ~/.claude, the
# real kit and the network are never touched: the remotes are local bare repositories.
#
# usage: tests/doctor.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0
fail=0

g() { git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

# world <name>: prints the path of a fresh, healthy world.
world() {
  local w="$T/$1"
  mkdir -p "$w/kit/scripts" "$w/home/.claude/rules" "$w/projects" "$w/bin" "$w/b1" "$w/b2"
  cp "$repo_root/doctor.sh" "$w/kit/doctor.sh"
  cp "$repo_root/scripts/backup-config.sh" "$w/kit/scripts/backup-config.sh"
  g init -q -b main "$w/kit"
  g init -q --bare -b main "$w/origin.git"
  g -C "$w/kit" add -A
  g -C "$w/kit" commit -q -m "initial"
  g -C "$w/kit" remote add origin "$w/origin.git"
  g -C "$w/kit" push -q -u origin main
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}]}}' >"$w/home/.claude/settings.json"
  printf '%s\n' '# test' >"$w/home/.claude/CLAUDE.md"
  printf '%s\n' '# a small always-on rule' >"$w/home/.claude/rules/small.md"
  printf '%s\n' '{"mcpServers":{"tokensave":{"type":"stdio","command":"tokensave","args":["serve"]}}}' >"$w/home/.claude.json"
  printf '#!/usr/bin/env bash\necho "tokensave: tokensave serve - Connected"\n' >"$w/bin/claude"
  printf '#!/usr/bin/env bash\necho "tokensave 7.16.0"\n' >"$w/bin/tokensave"
  printf '#!/usr/bin/env bash\necho "rtk 1.1.0"\n' >"$w/bin/rtk"
  chmod +x "$w/bin/"*
  : >"$w/b1/claude-config-20260101-000000.tar.gz"
  : >"$w/b2/claude-config-20260101-000000.tar.gz"
  echo "$w"
}

# run_doctor <world> [VAR=value ...]: the output of doctor.sh in that world, offline unless told otherwise.
run_doctor() {
  local w="$1"
  shift
  (cd "$w" && env HOME="$w/home" CLAUDE_CONFIG_DIR="$w/home/.claude" PROJECTS_DIR="$w/projects" \
    CLAUDE_CONFIG_BACKUP_DIRS="$w/b1:$w/b2" DOCTOR_OFFLINE=1 PATH="$w/bin:$PATH" "$@" \
    bash "$w/kit/doctor.sh" 2>&1) || true
}

expect() { # <label> <output> <regex>
  if grep -qE -- "$3" <<<"$2"; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n        expected /%s/ in:\n%s\n' "$1" "$3" "$(sed 's/^/        | /' <<<"$2" | sed -n '/resilience/,/MCP servers/p')"
  fi
}

refute() { # <label> <output> <regex>
  if grep -qE -- "$3" <<<"$2"; then
    fail=$((fail + 1))
    printf 'FAIL  %s\n        did not expect /%s/\n' "$1" "$3"
  else
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$1"
  fi
}

# --- a healthy world ----------------------------------------------------------------------------------
w=$(world healthy)
out=$(run_doctor "$w")
expect "healthy: backups are fresh" "$out" "✓ configuration backup in .*b1 is 0 day"
expect "healthy: both locations are checked" "$out" "✓ configuration backup in .*b2 is 0 day"
expect "healthy: no duplicated hooks" "$out" "✓ no duplicated hook entries"
expect "healthy: rules are inside the budget" "$out" "✓ always-on rules: "
expect "healthy: the kit repository is in step" "$out" "✓ .*/kit is in step with origin/main"
expect "healthy: tokensave and rtk by bare name" "$out" "✓ tokensave and rtk are registered by bare name"
touch "$w/b1/claude-config-20260101-000000.tar.gz" "$w/b2/claude-config-20260101-000000.tar.gz"

# --- backups ------------------------------------------------------------------------------------------
w=$(world backups)
touch -d '30 days ago' "$w/b1/claude-config-20260101-000000.tar.gz"
out=$(run_doctor "$w")
expect "stale backup is reported" "$out" "✗ newest configuration backup in .*b1 is 30 days old"
expect "the other location stays green" "$out" "✓ configuration backup in .*b2 is 0 day"
out=$(run_doctor "$w" DOCTOR_BACKUP_MAX_DAYS=60)
expect "the age limit is configurable" "$out" "✓ configuration backup in .*b1 is 30 day"
rm "$w/b2/claude-config-20260101-000000.tar.gz"
out=$(run_doctor "$w")
expect "an empty backup location is reported" "$out" "✗ no configuration backup in .*b2"

# --- duplicated hook entries ----------------------------------------------------------------------------
w=$(world dupes)
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]},{"hooks":[{"type":"command","command":"x"}]},{"hooks":[{"type":"command","command":"y"}]}]}}' \
  >"$w/home/.claude/settings.json"
out=$(run_doctor "$w")
expect "duplicated hook entries are reported" "$out" "✗ settings.json carries duplicated hook entries"
expect "the event and the count are named" "$out" "Stop: 1 duplicate hook entry"

# --- always-on rules budget -----------------------------------------------------------------------------
w=$(world budget)
head -c 6000 /dev/zero | tr '\0' 'x' >"$w/home/.claude/rules/big.md"
out=$(run_doctor "$w" DOCTOR_RULES_BUDGET=1000)
expect "an oversized always-on rule is reported" "$out" "✗ always-on rules are .* over the "
printf -- '---\npaths:\n  - "**/*.rs"\n---\n' >"$w/home/.claude/rules/scoped.md"
head -c 6000 /dev/zero | tr '\0' 'x' >>"$w/home/.claude/rules/scoped.md"
rm "$w/home/.claude/rules/big.md"
out=$(run_doctor "$w" DOCTOR_RULES_BUDGET=1000)
expect "a rule scoped with paths: does not count" "$out" "✓ always-on rules: "

# --- repositories against their remote ------------------------------------------------------------------
w=$(world repos)
echo local >"$w/kit/local.txt"
g -C "$w/kit" add -A && g -C "$w/kit" commit -q -m "local only"
out=$(run_doctor "$w")
expect "unpushed commits are noted" "$out" "1 commit\(s\) not pushed to origin/main"
g -C "$w/kit" push -q
g clone -q "$w/origin.git" "$w/other"
echo remote >"$w/other/remote.txt"
g -C "$w/other" add -A && g -C "$w/other" commit -q -m "from elsewhere"
g -C "$w/other" push -q
out=$(run_doctor "$w")
expect "offline, the last fetch is what counts" "$out" "✓ .*/kit is in step with origin/main"
out=$(run_doctor "$w" DOCTOR_OFFLINE=)
expect "online, doctor fetches and sees the remote commit" "$out" "1 commit\(s\) to pull from origin/main"
echo local2 >"$w/kit/local2.txt"
g -C "$w/kit" add -A && g -C "$w/kit" commit -q -m "diverge"
out=$(run_doctor "$w" DOCTOR_OFFLINE=)
expect "a diverged repository is a problem" "$out" "✗ .*/kit has diverged from origin/main \(1 ahead, 1 behind\)"

w=$(world noremote)
g -C "$w/kit" remote remove origin
out=$(run_doctor "$w")
expect "a repository without a remote is noted" "$out" "/kit: no remote, so the backups are the only copy"

w=$(world vault)
g init -q -b main "$w/home/vault"
g init -q --bare -b main "$w/vault.git"
echo note >"$w/home/vault/note.md"
g -C "$w/home/vault" add -A && g -C "$w/home/vault" commit -q -m "note"
g -C "$w/home/vault" remote add origin "$w/vault.git"
g -C "$w/home/vault" push -q -u origin main
printf '%s\n' '# protected' '~/vault' >"$w/home/.claude/protected-paths"
out=$(run_doctor "$w")
expect "a protected path that is a repository is compared too" "$out" "✓ ~/vault is in step with origin/main"

# --- tokensave and rtk registered by absolute path -------------------------------------------------------
w=$(world abspath)
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/home/someone/.local/bin/tokensave hook-stop"}]}],"PreToolUse":[{"matcher":"Agent","hooks":[{"type":"command","command":"command -v tokensave >/dev/null 2>&1 && tokensave hook-pre-tool-use || true"}]}]}}' \
  >"$w/home/.claude/settings.json"
printf '%s\n' '{"mcpServers":{"tokensave":{"type":"stdio","command":"/home/someone/.local/bin/tokensave","args":["serve"]}}}' >"$w/home/.claude.json"
out=$(run_doctor "$w")
expect "an absolute path in a hook is reported" "$out" "Stop hook: /home/someone/.local/bin/tokensave"
expect "an absolute path in an MCP server is reported" "$out" "MCP server tokensave: /home/someone/.local/bin/tokensave"
refute "a bare name in a hook is not reported" "$out" "PreToolUse hook:"

# --- the MCP check must not wait for a child of `claude mcp list` ----------------------------------------
w=$(world hang)
printf '#!/usr/bin/env bash\n(sleep 15) &\necho "tokensave: tokensave serve - Connected"\n' >"$w/bin/claude"
SECONDS=0
out=$(run_doctor "$w")
elapsed=$SECONDS
if [ "$elapsed" -lt 12 ]; then
  pass=$((pass + 1))
  printf 'PASS  doctor does not wait for a child that keeps the output open (%ss)\n' "$elapsed"
else
  fail=$((fail + 1))
  printf 'FAIL  doctor waited %ss for a child of claude mcp list\n' "$elapsed"
fi
expect "the MCP result is still read" "$out" "✓ all configured MCP servers connect"

printf '\ndoctor.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
