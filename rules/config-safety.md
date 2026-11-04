# The Claude Code configuration is not disposable

Claude Code loads its commands, rules, agents, skills, hooks and memories from the kit repository
and from the Claude configuration directory (`~/.claude`) that `install.sh` links into. Some files
there may exist nowhere else: the kit may have no remote, and layers and memories may not be
published anywhere.

- **Never delete or move** the kit repository, the Claude configuration directory, or its
  `commands/`, `rules/`, `agents/`, `skills/` and `hooks/` directories, `settings.json`, the manifest
  or a `memory/` directory — not even to fix broken links, and never by telling the user to. Broken
  or absolute links are fixed by `./install.sh --check` then `./install.sh` in the kit. A
  config-protection hook may refuse such commands; do not work around it.
- **Before changing** the kit or the Claude configuration, take a snapshot
  (`scripts/backup-config.sh` in the kit) and **remind the user**, in one line, that these files are
  what Claude uses and must not be deleted. Keep backups on a different disk or location than the
  configuration, never only inside a container: it disappears on rebuild.
- New personal or project-specific commands and rules go into a layer under `layers/<name>/` and are
  linked by `install.sh`, never written loose into the Claude configuration directory.
