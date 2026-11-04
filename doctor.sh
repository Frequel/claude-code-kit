#!/usr/bin/env bash
# Health check for the whole Claude Code setup: the kit, the user config, the MCP servers,
# and every repository's CLAUDE.md. Read-only. Exit 1 if anything is broken.
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS="${PROJECTS_DIR:-$HOME/projects}"
problems=0
note()  { printf '  %s\n' "$1"; }
bad()   { printf '  ✗ %s\n' "$1"; problems=$((problems+1)); }
good()  { printf '  ✓ %s\n' "$1"; }

echo "== kit =="
command -v python3 >/dev/null 2>&1 && good "python3 present (the guard and protect-config hooks need it)" \
  || bad "python3 missing: the guard and protect-config hooks silently allow everything without it"
for d in commands skills agents rules hooks templates; do
  [ -d "$KIT_ROOT/$d" ] && good "$d/ ($(find "$KIT_ROOT/$d" -maxdepth 1 -mindepth 1 | wc -l) entries)" || bad "$d/ missing"
done
python3 -c "import json,sys;json.load(open('$KIT_ROOT/hooks/hooks.json'))" 2>/dev/null \
  && good "hooks.json is valid JSON" || bad "hooks.json is not valid JSON"
for s in "$KIT_ROOT"/hooks/scripts/*.sh; do
  bash -n "$s" 2>/dev/null && [ -x "$s" ] || bad "hook script broken or not executable: $(basename "$s")"
done

echo "== skills are folders, not flat files =="
flat=$(find "$KIT_ROOT/skills" "$CLAUDE_DIR/skills" -maxdepth 1 -name '*.md' 2>/dev/null | grep -v synced | wc -l)
[ "$flat" -eq 0 ] && good "no flat .md in any skills/ directory" \
                  || bad "$flat flat .md file(s) in a skills/ directory — those never load"
for d in "$KIT_ROOT"/skills/*/; do
  [ -f "$d/SKILL.md" ] || bad "skill without SKILL.md: $(basename "${d%/}")"
done
repo_flat=$(find "$PROJECTS" -path '*/.claude/skills/*.md' -not -path '*/node_modules/*' 2>/dev/null | wc -l)
[ "$repo_flat" -eq 0 ] && good "no inert skills left in the repositories" \
                       || bad "$repo_flat inert .claude/skills/*.md file(s) still in repositories"

echo "== user configuration =="
[ -f "$CLAUDE_DIR/.claude-kit-manifest" ] && good "kit installed ($(wc -l < "$CLAUDE_DIR/.claude-kit-manifest") entries)" \
                                          || note "kit not installed at user level (fine if you use plugin mode + --rules-only)"
if [ -f "$CLAUDE_DIR/.claude-kit-layers" ]; then
  for l in $(cat "$CLAUDE_DIR/.claude-kit-layers"); do
    [ -f "$KIT_ROOT/layers/$l/layer.json" ] && good "layer $l present" || bad "layer $l is selected but layers/$l/layer.json is missing"
  done
else
  note "no layers selected (core only); see ./install.sh --list-layers"
fi
lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null || echo 0)
[ "$lines" -le 120 ] && good "~/.claude/CLAUDE.md is $lines lines" || bad "~/.claude/CLAUDE.md is $lines lines — move detail into rules/ or skills/"
[ -d "$CLAUDE_DIR/rules" ] && good "rules/ present ($(ls "$CLAUDE_DIR"/rules/*.md 2>/dev/null | wc -l) files)" || bad "no ~/.claude/rules/"
python3 -c "import json;json.load(open('$CLAUDE_DIR/settings.json'))" 2>/dev/null \
  && good "settings.json is valid JSON" || bad "settings.json is not valid JSON"
junk=$(find "$CLAUDE_DIR" "$PROJECTS" -name '*:Zone.Identifier' 2>/dev/null | wc -l)
[ "$junk" -eq 0 ] && good "no Zone.Identifier junk" || bad "$junk Zone.Identifier file(s)"

echo "== duplicated configuration in repositories =="
dupes=0
for f in "$KIT_ROOT"/commands/*.md "$KIT_ROOT"/agents/*.md; do
  sum=$(md5sum "$f" | cut -d' ' -f1); name=$(basename "$f")
  while IFS= read -r c; do
    [ "$(md5sum "$c" | cut -d' ' -f1)" = "$sum" ] && { echo "    duplicate of $name: ${c#$PROJECTS/}"; dupes=$((dupes+1)); }
  done < <(find "$PROJECTS" -path "*/.claude/*/$name" 2>/dev/null)
done
[ "$dupes" -eq 0 ] && good "no exact copies of kit files in repositories" || bad "$dupes exact cop(ies) of kit files in repositories"

echo "== MCP servers =="
if command -v claude >/dev/null 2>&1; then
  mcp=$(timeout 60 claude mcp list 2>&1)
  # tokensave refuses to start when the working directory is not an indexed project, so the
  # health check fails purely because of where doctor.sh was launched from. Re-check it from a
  # directory that IS indexed before believing the failure — a check that cries wolf stops
  # being read.
  if printf '%s\n' "$mcp" | grep -qi 'tokensave.*\(fail\|closed\)'; then
    indexed=$(find "$PROJECTS" -maxdepth 5 -type d -name .tokensave -print -quit 2>/dev/null)
    if [ -n "$indexed" ] && (cd "$(dirname "$indexed")" && timeout 60 claude mcp get tokensave 2>&1 | grep -q 'Connected'); then
      mcp=$(printf '%s\n' "$mcp" | grep -vi 'tokensave')
      note "tokensave connects from an indexed project; it only refused from $(pwd), which is not one — ignored"
    fi
  fi
  if printf '%s\n' "$mcp" | grep -qiE 'fail|error|closed'; then
    printf '%s\n' "$mcp" | sed 's/^/    /'
    bad "an MCP server is not connecting"
    # tokensave refuses to start when the working directory is neither an indexed project nor
    # registered in ~/.tokensave/global.db. The dev containers persist that directory on a named
    # volume, so it normally survives a rebuild; it comes back empty only when the volume itself is
    # new or was removed. The per-repo .tokensave/ indexes live under ~/projects and always survive,
    # so one sync in any indexed repo rebuilds the registry from them.
    if printf '%s\n' "$mcp" | grep -qi 'tokensave.*\(fail\|closed\)' && command -v tokensave >/dev/null 2>&1; then
      note "tokensave: if ~/.tokensave came back empty (new or removed volume), run 'tokensave sync' inside any indexed repo to rebuild the global registry, then re-check"
    fi
  else
    good "all configured MCP servers connect"
  fi
else
  note "claude CLI not on PATH — skipped"
fi
command -v tokensave >/dev/null 2>&1 && good "tokensave binary present ($(tokensave --version 2>/dev/null))" || bad "tokensave not on PATH"
# The rtk PreToolUse hook is registered as the bare command `rtk hook claude`, which is the only
# form rtk's own installer recognises — so a missing binary is a real problem, not a silent skip.
command -v rtk >/dev/null 2>&1 && good "rtk binary present ($(rtk --version 2>/dev/null))" \
  || bad "rtk not on PATH, but settings.json registers the bare 'rtk hook claude' hook — every Bash call will error"
indexed=$(find "$PROJECTS" -maxdepth 5 -type d -name .tokensave 2>/dev/null | wc -l)
note "$indexed repositor(ies) have a tokensave index"

echo "== secrets in CLAUDE.md =="
# Agents writing these files have put AWS account ids in them despite being told not to.
# A guidance file is shared material: it must carry no identifier that a stranger could use.
leaky=$(find "$PROJECTS" -maxdepth 6 -name CLAUDE.md -not -path '*/node_modules/*' \
  -exec grep -lE "AKIA[0-9A-Z]{12}|arn:aws|[^0-9][0-9]{12}[^0-9]" {} \; 2>/dev/null)
if [ -z "$leaky" ]; then
  good "no account id, ARN or access key in any CLAUDE.md"
else
  printf '%s\n' "$leaky" | sed "s|$PROJECTS/|    |"
  bad "a CLAUDE.md carries an account id, an ARN or an access key"
fi

echo "== repository CLAUDE.md =="
while IFS= read -r repo; do
  r=$(dirname "$repo"); name=${r#$PROJECTS/}
  # A git repo nested inside another one is vendored upstream code. It is not ours to document.
  parent=$(dirname "$r")
  while [ "$parent" != "$PROJECTS" ] && [ "$parent" != "/" ]; do
    [ -e "$parent/.git" ] && { echo "    vendored, skipped: $name"; continue 2; }
    parent=$(dirname "$parent")
  done
  # A git worktree has a .git FILE pointing at its parent, not a directory. It shares the
  # parent's CLAUDE.md and must not be counted separately. Worktrees created on the host also
  # record a host path, which does not resolve inside a dev container — report those.
  if [ -f "$r/.git" ]; then
    if git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
      echo "    worktree, skipped: $name"
    else
      echo "    BROKEN worktree (its gitdir does not resolve here — 'git worktree prune' in the parent repo): $name"
    fi
    continue
  fi
  # A repo nobody has touched in a year does not earn a CLAUDE.md.
  if [ -z "$(git -C "$r" log --since='12 months ago' --oneline 2>/dev/null | head -1)" ]; then
    [ -f "$r/CLAUDE.md" ] || { echo "    dormant, skipped: $name (last commit $(git -C "$r" log -1 --format=%ad --date=short 2>/dev/null))"; continue; }
  fi
  if [ ! -f "$r/CLAUDE.md" ]; then echo "    no CLAUDE.md: $name"; continue; fi
  # The block rtk init writes is generic and duplicates ~/.claude/rules/rtk.md.
  grep -q 'rtk-instructions' "$r/CLAUDE.md" && echo "    carries the generated rtk block (remove it, it duplicates rules/rtk.md): $name"
  n=$(wc -l < "$r/CLAUDE.md")
  # The real signal is runnable commands, whatever the heading is called.
  fences=$(grep -c '^```' "$r/CLAUDE.md")
  if [ "$fences" -lt 2 ]; then
    echo "    no runnable commands ($n lines): $name"
  elif [ "$n" -lt 40 ]; then
    echo "    thin ($n lines): $name"
  else
    # Bytes, not lines: the worst offender found so far was 41 KB in 321 lines, because prose
    # lines run long. Lines under-report the real cost of loading this file every session.
    b=$(stat -c%s "$r/CLAUDE.md")
    if [ "$b" -gt 16384 ]; then
      echo "    oversized ($((b/1024)) KB in $n lines — move reference material into the repo's docs/): $name"
    fi
  fi
done < <(find "$PROJECTS" -maxdepth 5 -name .git -not -path '*/node_modules/*' 2>/dev/null)

echo
[ "$problems" -eq 0 ] && echo "OK — no problems found." || echo "$problems problem(s) found."
exit $(( problems > 0 ))
