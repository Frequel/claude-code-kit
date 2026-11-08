# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). `VERSION`, `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` always carry the same number.

## [Unreleased]
### Fixed

- `doctor.sh` no longer captures `claude mcp list` through a command substitution. The output goes to a
  temporary file, stdin is `/dev/null` and the timeout sends SIGKILL, so a child process that keeps the
  pipe open cannot hang the MCP check.

## [1.1.0] - 2026-11-05
### Added

- `guard-allow-remotes`: per-config or per-layer URL patterns that exempt matching repositories from the
  protected-branch rule of the guard hook. Force pushes, `--mirror` and `--all` stay refused.

### Fixed

- `install.sh` creates the Claude config directory when it does not exist, so the first install on a new
  machine no longer fails.
- `CLAUDE.md` is tracked again; it had been dropped from the clean copy by a global git ignore.

## [1.0.0] - 2026-11-03

### Added

- Layers: swappable specialisations under `layers/<name>/`, each normally its own git repository.
  The core `.gitignore` excludes `layers/*` except the documented `layers/example`.
- `install.sh --layers a,b` (installed in order, later layers win), `--list-layers`, and a remembered
  selection in `~/.claude/.claude-kit-layers`. `layer.json` supports `requires`, checked at install.
- Hook merge from `hooks/hooks.json` and from every layer's `hooks/hooks.json`.
- Command-aware `guard` and `protect-config` hooks, built on a shared command parser
  (`hooks/scripts/lib/cmdparse.py`), with the test suite `tests/hooks.sh`.
- `protected-paths` files (in the config directory or in a layer): extra folders `protect-config`
  refuses to delete or move.
- Environment variables `CLAUDE_CONFIG_DIR`, `CLAUDE_KIT_ROOT`, `CLAUDE_KIT_PROJECTS_DIR` and
  `PROJECTS_DIR`.
- `docs/layers.md` (layer authoring guide), `CHANGELOG.md`, `LICENSE` (MIT), a README troubleshooting
  section for the tokensave `Stop` hook issue.

### Changed

- The core is now generic and open-source ready: stack-aware commands, skills, agents, rules, hooks
  and templates only. Company-specific and personal content moved out of the core into layers.
- The plugin is renamed `claude-code-kit` (it was named after the company layer's origin).
- The manifest is now `~/.claude/.claude-kit-manifest`. A legacy `.<name>-kit-manifest` is migrated
  automatically on the next install (the old file is kept with a `.bak` suffix).
- The `orient` hook is split: the core prints repository, branch and stack; a layer can add its own
  `SessionStart` hook for anything more.
- The old layout had a `personal/` folder inside the kit; it is now a regular layer.
- `/kit-doctor` resolves the kit location through the installed link, so the kit's folder name and
  position no longer matter.
- The kit's folder name no longer matters; only the relative position of `~/.claude` and the kit must
  match between host and containers.

### Fixed

- `guard` and `protect-config` false positives: text in quotes, heredocs and `echo` no longer
  matches, and the guard checks the repository the command acts on (following `cd` and `git -C`)
  instead of the session's working directory.
- `git push --force-with-lease` is allowed; `-f`, `--force` and `+refspec` pushes are refused.

### Removed

- Company and personal commands, rules, skills, agents and docs from the core tree (they live in
  layers now).
