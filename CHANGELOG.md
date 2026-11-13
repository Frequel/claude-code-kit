# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). `VERSION`, `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` always carry the same number.

## [Unreleased]
### Added

- `plugins.json` in the core or in a layer declares marketplaces and plugins; `install.sh` merges them into
  `settings.json` (`extraKnownMarketplaces`, `enabledPlugins`) without replacing or re-enabling anything the user
  set. `layers/personal` declares the 11 plugins in use (the official marketplace plus `egm@egm`). `tests/plugins.sh`: 8 cases.

- The guard hook refuses `tokensave doctor|install|reinstall|upgrade` and `rtk init -g`, which rewrite the
  configuration shared with the dev containers with host-only paths. It follows `cd`, `bash -c`, `env`, `sudo`
  and `rtk` (also `rtk proxy`); the per-project forms stay allowed. 26 cases in `tests/hooks.sh`.

- `doctor.sh` "resilience" section: the newest configuration backup in each backup location must be recent
  (`DOCTOR_BACKUP_MAX_DAYS`, default 7), `settings.json` must carry no duplicated hook entries, the always-on
  rules must stay inside a size budget (`DOCTOR_RULES_BUDGET`, default 24 KB), and the kit, its layers and every
  protected path that is a git repository are compared with their remote (a diverged one is a problem;
  `DOCTOR_OFFLINE=1` skips the fetch).
- `scripts/backup-config.sh --list-destinations`, so `doctor.sh` reads the same locations the backup writes to.
- `tests/doctor.sh`: 25 cases for `doctor.sh` in throw-away worlds, including one that fails on the old
  command-substitution capture of `claude mcp list`.
- `rules/exploration.md` states the precedence of the tokensave-written `rules/tokensave.md` over the kit's
  rules for code exploration in an indexed repository; `rules/delegation.md` points to it.

- `doctor.sh` fails when `settings.json` or `~/.claude.json` names `tokensave` or `rtk` by absolute path in a
  hook or an MCP server. The configuration is shared with the dev containers, where the home directory and the
  binary location differ, so only bare names resolve on both sides. `tokensave doctor` writes absolute paths.

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
