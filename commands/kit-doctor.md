---
description: Check that the Claude Code configuration is healthy (kit, rules, hooks, MCP, per-repo CLAUDE.md)
allowed-tools: Bash, Read, Glob
model: haiku
---

Run the kit's health check and report what is broken.

```bash
KIT="$(cd "$(dirname "$(readlink -f "$HOME/.claude/commands/kit-doctor.md")")/.." && pwd)"
bash "$KIT/doctor.sh" ${ARGUMENTS:-}
```

If `$KIT/doctor.sh` is not there, say so rather than improvising a replacement.

Read the output and report it in priority order: things that are silently broken first (a skill that cannot load, a hook that never fires, an MCP server that is down, a `CLAUDE.md` whose commands do not run), then drift, then cosmetics. For each, say what to run to fix it. Do not fix anything unless asked.
