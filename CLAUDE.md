# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

`claude-code-kit` is a generic Claude Code configuration: slash commands, skills, subagents, memory
rules, quality hooks and per-stack `CLAUDE.md` templates. It is consumed either as a plugin or
symlinked into `~/.claude` by `install.sh`, and specialised through **layers** (`layers/<name>/`,
each normally its own git repository). `README.md` explains both paths and `docs/layers.md` the
layers.

This repo configures the tool; it ships no application code.

## Commands

```bash
bash tests/hooks.sh           # hook test suite (must stay green)
bash tests/doctor.sh          # doctor.sh against throw-away worlds, no network (must stay green)
./install.sh --check          # is the kit installed, drifted, or missing anything
./install.sh --user           # (re)install into ~/.claude — symlinks by default
./install.sh --layers a,b     # install the core plus these layers (remembered)
./install.sh --list-layers    # layers available and in use
./doctor.sh                   # full health check: skills, hooks, MCP, duplicates, repo CLAUDE.md
./propagate.sh <repo>         # dry run: what the kit would clean up in that repository
./propagate.sh --apply <repo> # do it, backing up to $TMPDIR first
bash -n hooks/scripts/*.sh    # syntax check, the only "build" this repo has
```

Test a hook the way Claude Code calls it — JSON on stdin:

```bash
echo '{"tool_input":{"command":"git commit -m x"},"cwd":"/path/to/a/repo/on/master"}' | bash hooks/scripts/guard.sh
echo '{"cwd":"/path/to/a/repo"}' | bash hooks/scripts/orient.sh
```

## Layout

| Directory | Loaded by Claude Code when |
|---|---|
| `commands/` | the user types the slash command |
| `skills/<name>/SKILL.md` | Claude judges the description relevant — **a flat `.md` here never loads** |
| `agents/` | something delegates to them; each declares its own `model:` |
| `rules/` | always, or when a file matching its `paths:` frontmatter is read |
| `hooks/` | the harness runs them; `${CLAUDE_PLUGIN_ROOT}` is rewritten to `$HOME/...` on install |
| `layers/` | `install.sh --layers` installs them after the core. Each layer is a separate git repo ignored by the core (only `layers/example` is tracked); never shipped by the plugin |
| `templates/` | `propagate.sh` copies them into a repo that has no `CLAUDE.md` |
| `scripts/` | `backup-config.sh`, called by the protect-config hook or by hand |
| `tests/` | `hooks.sh`, the hook test suite |
| `docs/` | `layers.md`, the layer authoring guide |

## Gotchas

- **Skills are folders.** A `skills/foo.md` file is silently ignored by Claude Code — that is the
  bug this repo was created to fix. `doctor.sh` checks for it; do not reintroduce it.
- **Plugins cannot ship `rules/` or layers.** In plugin mode the rules must still be installed with
  `./install.sh --rules-only`. Only the core's `commands/`, `skills/`, `agents/` and `hooks/` travel
  with a plugin.
- **Layers are separate repos, ignored by the core.** Never `git add` anything under `layers/`
  except `layers/example`, and keep company or personal content out of the core tree: the core must
  stay generic and free of names, hosts and secrets.
- **A hook that writes to stdout injects that text into the session.** Keep hooks silent on the
  happy path, and never let one fail loudly: every script exits 0 unless it means to block. The one
  deliberate exception is `delegation-check.sh` (UserPromptSubmit), whose reminder is the point; keep it
  short, since it is paid on every prompt.
- **`guard.sh` blocks; a `Stop` hook must not.** A `Stop` hook that exits 2 keeps the conversation
  going and can loop. Stop hooks only emit `systemMessage`.
- **guard and protect-config parse the command** through `hooks/scripts/lib/cmdparse.py`, so quotes,
  heredocs and `echo` never match, and `cd` / `git -C` are followed. A parse error allows the
  command. Change the parser and the hooks together, with a case in `tests/hooks.sh`.
- **`guard-allow-remotes` is an explicit consent.** Repos whose remote matches a pattern (config dir or a
  layer in use) may use protected branches; force, `--mirror` and `--all` stay refused. Never add a
  pattern without the owner asking for it.
- **Keep `tests/hooks.sh` green.** Every behaviour change in a hook needs a test case.
- **Keep `tests/doctor.sh` green.** Every new check in `doctor.sh` needs a case there: it builds a fake kit,
  home and remote, so it never reads the real configuration or the network.
- **`rules/tokensave.md` is written by tokensave, not by the kit.** Never edit it; precedence over the kit's
  own rules is stated in `rules/exploration.md`.
- **`install.sh` owns only what is in `~/.claude/.claude-kit-manifest`.** Never make it delete or
  overwrite a path that is not listed there — a personal file with the same name must win. The
  manifest is migrated from the legacy name on install.
- **One `~/.claude`, two homes.** If it is bind-mounted into dev containers, symlinks must stay
  relative, manifest entries relative to `~/.claude`, hook commands on `$HOME`; `~/.claude` and the
  kit must keep the same relative position on both sides. `--check` flags `BROKEN` and `ABSOLUTE`.
- **Layer hooks use `${CLAUDE_PLUGIN_ROOT}/layers/<name>/hooks/scripts/<x>.sh`**, never an absolute path.
- **Versions stay equal** in `VERSION`, `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json`; record changes in `CHANGELOG.md`.
- Symlink mode is the default on purpose: copies drift.
- Everything written here is English, and nothing in this repo may contain a secret, a hostname,
  an IP address, an account id or a customer name.
