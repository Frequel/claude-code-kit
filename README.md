# claude-code-kit

A generic, versioned Claude Code configuration: slash commands, skills, subagents, quality hooks,
standing rules and per-stack `CLAUDE.md` templates. One source of truth, installed by symlink (or
as a plugin), and specialised for a person or a team through swappable **layers**.

The core is deliberately neutral: it knows about Rust, Go, Python and TypeScript, about git hygiene
and about delegating work to subagents, and nothing about any company or personal workflow. Those
live in layers, which are separate git repositories the core ignores.

## Why it exists

Copies of the same commands and agents, pasted into every repository, drift into incompatible
generations. Skills written as flat `.md` files are never loaded by Claude Code. And the rules that
matter most (never commit to `master`, always run the gate) are prose a session may skip. The kit
fixes distribution (one place, symlinked or installed as a plugin) and enforcement (hooks the harness
runs, not sentences Claude may ignore).

## Install

```bash
git clone <your-remote>/claude-code-kit.git ~/projects/claude-code-kit
cd ~/projects/claude-code-kit
./install.sh --user                 # core only
./install.sh --layers mine          # core + your layer(s), remembered for later runs
```

Everything is symlinked into `~/.claude/`, so `git pull` in the kit updates every session on the
machine. Restart Claude Code, then run `/kit-doctor`.

| Flag | Effect |
|---|---|
| `--user` | Install into `~/.claude` (the default). |
| `--layers a,b` | Also install `layers/a` then `layers/b`; later layers win on a name clash. Remembered in `~/.claude/.claude-kit-layers`. `--layers none` returns to the core only. |
| `--list-layers` | Show the layers available under `layers/` and the ones in use. |
| `--check` | Report what is installed, missing, broken, absolute or drifted. Changes nothing. |
| `--copy` | Copy files instead of symlinking (for environments where symlinks do not work). |
| `--rules-only` | Install only `rules/` (companion of plugin mode). |
| `--uninstall` | Remove exactly what the manifest lists, and the kit's hooks. |

The installer owns only what is listed in the manifest `~/.claude/.claude-kit-manifest`. A file of
yours with the same name is reported as skipped and left alone. Hooks from `hooks/hooks.json` and
from each layer's `hooks/hooks.json` are merged into `~/.claude/settings.json`.
Plugins declared in `plugins.json` (core or layer) are merged into the same file; see `docs/layers.md`.

### Plugin mode

```
/plugin marketplace add ~/projects/claude-code-kit
/plugin install claude-code-kit@claude-code-kit
```

Commands arrive namespaced (`/claude-code-kit:check`). Only the core's `commands/`, `skills/`,
`agents/` and `hooks/` travel with the plugin. Plugins cannot ship `rules/`, and layers are not part
of the plugin, so both still need `./install.sh --rules-only` / `./install.sh --layers ...`.

### Host and dev containers

If `~/.claude` is bind-mounted into dev containers, the links the installer writes are **relative**,
manifest entries are relative to `~/.claude`, and hook commands go through `$HOME`. The kit and
`~/.claude` must therefore keep the same relative position on both sides (for example both under
`$HOME`); the kit's folder name does not matter. Install from either side, and use
`./install.sh --check` to find `BROKEN` or `ABSOLUTE` entries. Never fix broken links by deleting
directories: rerun the installer.

## What is inside (core)

| Directory | Contents | Loads when |
|---|---|---|
| `commands/` | `/architect`, `/dev`, `/review`, `/refactor`, `/scaffold`, `/document`, `/new-feature`, `/code_diagnosis`, `/check`, `/docker-build`, `/commit-msg`, `/go`, `/orchestrate`, `/team`, `/team-feature`, `/fanout`, `/kit-doctor` | You type them |
| `skills/` | `build-check` (syntax, lint and tests after edits), `debug` (diagnose errors and failures) | Claude judges them relevant |
| `agents/` | `staff-reviewer` (Opus, adversarial review), `rust-service-dev`, `go-service-dev`, `python-service-dev`, `test-suite-architect` (Sonnet), `gate-runner` (Haiku, returns only failures) | Delegated to |
| `rules/` | `git.md`, `exploration.md`, `config-safety.md`, `delegation.md` always; `rust.md`, `go.md`, `python.md`, `typescript.md` when you touch matching files | Automatically |
| `hooks/` | format after edits, command-aware branch guard, configuration protection, session orientation | Automatically |
| `templates/` | `CLAUDE.base.md` plus one skeleton per stack (Rust, Go, Python, TypeScript, infra) | `propagate.sh` copies them |
| `layers/` | Your specialisations; only `layers/example` is part of the kit | `install.sh --layers` |
| `scripts/` | `backup-config.sh` | The protect hook, or by hand |
| `tests/` | `hooks.sh`, the hook test suite | You run it |

## Hooks

All hooks are silent on the happy path and exit 0 unless they mean to block.

- **format** (PostToolUse on edits): `rustfmt`, `gofmt`, `ruff format`, `prettier`, `shfmt`, whichever
  is installed; missing tools are skipped silently.
- **guard** (PreToolUse on Bash): refuses `git commit` and `git push` on `master`, `main` or
  `develop` of the repository the command **actually acts on** (it follows `cd` and `git -C`), and
  refuses force pushes (`-f`, `--force`, `+refspec`). `--force-with-lease` is allowed. A repository
  whose remote URL matches a pattern in a `guard-allow-remotes` file (config directory or a layer in
  use) is exempt from the protected-branch rule only; force, `--mirror` and `--all` stay refused.
  It also refuses the self-repair commands of third-party tools that rewrite the configuration shared
  with the dev containers: `tokensave doctor|install|reinstall|upgrade` and `rtk init -g` (the
  per-project forms `tokensave init`, `tokensave sync` and `rtk init` stay allowed). The reason tells
  Claude to ask the user to run it themselves with `! <command>` after a snapshot.
- **protect-config** (PreToolUse on Bash and edits): refuses deleting or moving the Claude config
  directory's `commands`, `rules`, `agents`, `skills`, `hooks`, `settings`, manifests, `plugins` and
  memories; the kit root, its top-level folders, its layer folders and `.git`; and any folder listed
  in a `protected-paths` file (one path per line, `~` allowed, `#` comments) in the config directory
  or in a layer in use. Editing single files inside the kit is allowed. Before a change it takes a
  snapshot through `scripts/backup-config.sh` (at most hourly) and reminds once per session.
- **orient** (SessionStart): prints repository, branch and detected stack, and warns when the repo
  has no `CLAUDE.md`. Active under `~/projects` (override with `CLAUDE_KIT_PROJECTS_DIR`).

guard and protect-config parse the command (`hooks/scripts/lib/cmdparse.py`), so text inside quotes,
heredocs or `echo` never matches. If parsing fails the command is allowed.

## Environment variables

| Variable | Default | Used by |
|---|---|---|
| `CLAUDE_CONFIG_DIR` | `~/.claude` | install, doctor, backup, hooks |
| `CLAUDE_KIT_ROOT` | the kit's own folder | the test suite |
| `CLAUDE_KIT_PROJECTS_DIR` | `~/projects` | `orient.sh` |
| `PROJECTS_DIR` | `~/projects` | `doctor.sh` |
| `CLAUDE_CONFIG_BACKUP_DIRS` | see `scripts/backup-config.sh` | backup destinations, colon-separated |

## Layers

A layer is a folder with the same shape as the core plus a `layer.json`; it installs after the core
and wins on name clashes. Start from the sample:

```bash
cp -r layers/example layers/mine && $EDITOR layers/mine/layer.json
./install.sh --layers mine
```

The full guide is [`docs/layers.md`](docs/layers.md). Because the core's `.gitignore` excludes
`layers/*` (except `layers/example`), sharing the core repository can never leak a layer.

## Tools

```bash
./doctor.sh                       # health check: skills, hooks, MCP, duplicates, repo CLAUDE.md
./propagate.sh <repo>             # dry run: what the kit would clean up in that repository
./propagate.sh --apply <repo>     # do it, backing up to $TMPDIR first
bash tests/hooks.sh               # hook test suite
```

## Optional tools

The kit integrates two public tools when they are installed and does nothing when they are not:
[tokensave](https://github.com/aovestdipaperino/tokensave) (code-graph MCP server) and `rtk` (a
token-saving command proxy). Their hooks use the guarded form
`command -v X >/dev/null 2>&1 && X hook... || true`.

## Troubleshooting

**tokensave keeps adding a broken `Stop` hook to `settings.json`.** tokensave (6.x and 7.16.0
verified) appends `{"command":"command","args":["hook-stop"]}` to `~/.claude/settings.json` on every
CLI run such as `tokensave status` or `tokensave init`, unless a `Stop` hook containing the text
`tokensave hook-stop` already exists. Fix: add the guarded hook
`command -v tokensave >/dev/null 2>&1 && tokensave hook-stop || true` as a `Stop` command, then
delete the broken entries.

Related rules:

- Register the MCP server by name: `claude mcp add --scope user tokensave -- tokensave serve`.
- Never run `tokensave doctor`, `install` or `upgrade` against a shared config: they rewrite
  `settings.json`.
- Never run `rtk init -g`; the kit's hooks already cover it.
- If `rtk gain` says "command not found" while `rtk --version` works, a different tool named `rtk`
  is on the PATH; check `which rtk`.

**A command or rule works on the host but not in a container.** An absolute link or hook path
resolves on one side only. Run `./install.sh --check`, then `./install.sh`.

**A layer is not picked up.** `./install.sh --list-layers` shows what is in use; the choice is stored
in `~/.claude/.claude-kit-layers`.

## Versioning and conventions

Semantic versions live in `VERSION`, `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json`, and are kept equal. Changes are recorded in
[`CHANGELOG.md`](CHANGELOG.md). Licensed under the MIT license (`LICENSE`).

Everything written in this repository is English, and nothing in it may contain a secret, hostname,
IP address, account id or customer name. Work on `feature/*`, `bugfix/*` or `hotfix/*`; the guard
hook stops commits on protected branches.
