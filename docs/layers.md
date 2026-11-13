# Layers

A layer is a folder under `layers/<name>/` with the same shape as the core. It holds everything that
is specific to a person or a team (house rules, internal commands, domain skills, extra hooks) so
the core stays generic. `install.sh --layers a,b` installs the core first, then each layer in the
order given; **a later layer wins** when two files have the same name, and a layer overrides the
core.

## Directory shape

```
layers/<name>/
  layer.json          {"name", "description", "requires": []}
  protected-paths     optional: extra folders protect-config must never delete or move
  guard-allow-remotes optional: remote URL patterns whose repos may commit/push on protected branches
  rules/*.md          standing rules (always-on, or path-scoped through `paths:` frontmatter)
  commands/*.md       slash commands
  agents/*.md         subagents (declare `model:` in the frontmatter)
  skills/<skill>/SKILL.md
  hooks/hooks.json    hook groups, merged into ~/.claude/settings.json
  hooks/scripts/*.sh  the scripts those hooks run
  plugins.json        optional: marketplaces and plugins declared in ~/.claude/settings.json
  templates/          per-repo CLAUDE.md templates, if you use them
  docs/ , README.md   anything else; the installer ignores it
```

Every part is optional except `layer.json`.

## Plugins

`plugins.json` (in the core or in a layer) declares Claude Code plugins that should arrive with the kit:

```json
{
  "marketplaces": { "egm": { "source": { "source": "github", "repo": "google/elephant-goldfish-model" } } },
  "plugins": ["egm@egm"]
}
```

`install.sh` merges it into `~/.claude/settings.json` as `extraKnownMarketplaces` and `enabledPlugins`;
Claude Code installs the declared plugins from there. The merge only adds: a marketplace you registered
under the same name is kept, and a plugin you enabled or disabled yourself is never flipped. Running it
twice changes nothing, and `--rules-only` skips it. `--uninstall` leaves plugins in place, because the
installer cannot tell which of them you would still want. Remove one by hand from `enabledPlugins`.

## Rules for each part

**Names and overrides.** A file is installed under its own name, so `layers/mine/commands/check.md`
replaces the core's `/check` for as long as the layer is in use. Use that deliberately, and prefix
new files with the layer name (`mine-git.md`) when you want to add rather than replace. Among
layers, the one listed last wins. A file you wrote by hand in `~/.claude` with the same name is never
overwritten: the installer reports it as skipped.

**Skills are folders.** `skills/<skill>/SKILL.md`; a flat `.md` file is never loaded by Claude Code.

**`layer.json`.** `name` equals the folder name (letters, digits, `.`, `_`, `-`, starting with a
letter or digit). `requires` lists layers that must also be in use; the installer warns when one is
missing.

**Hooks.** `hooks/hooks.json` has the same format as the core's and is merged into `settings.json`.
Every command must start with
`bash "${CLAUDE_PLUGIN_ROOT}/layers/<name>/hooks/scripts/<script>.sh"`, which the installer rewrites
to a `$HOME`-based path that works on the host and in containers. Keep scripts silent on the happy
path and exit 0 unless they mean to block. A `Stop` hook must never exit 2.

**`protected-paths`.** One path per line, `~` allowed, `#` starts a comment. The protect-config hook
refuses commands that delete or move any listed folder, as long as the layer is in use. Use it for
data that exists nowhere else (a notes folder, a private checkout). A file with the same name in the
config directory (`~/.claude/protected-paths`) applies to every session.

**`guard-allow-remotes`.** One `fnmatch` pattern per line, `#` starts a comment, matched against the URL of
the remote the push targets (`origin` when none is named) and against the same URL without `.git`, for example
`git@github.com:Me/my-notes*`. A repository that matches may take commits and pushes on `main`, `master` and
`develop`. Force pushes, `--mirror` and `--all` stay refused for it. It is an explicit consent: list only
repositories you own and are happy to let Claude publish to. Without the file nothing changes. A file with
the same name in the config directory applies to every session.

**Keep layers private.** Layers are installed per machine; do not put
secrets, hostnames or account ids in them if there is any chance they will be shared.

## Choosing and ordering layers

```bash
./install.sh --list-layers            # available and in use
./install.sh --layers base,mine       # core, then base, then mine (mine wins)
./install.sh --layers none            # back to the core only
./install.sh --check                  # verify
```

The selection is stored in `~/.claude/.claude-kit-layers` and reused by later runs of `install.sh`,
so `git pull` followed by `./install.sh` keeps the same layers.

## Backing up and sharing

Each layer is its own git repository. The core's `.gitignore` excludes `layers/*` except
`layers/example`, so nothing under a layer can reach the core's history by accident.

- **Back up a layer:** `git init` inside it, commit, and push to your own private remote.
- **Share the kit publicly:** share the core repository only. Layers stay with their own remotes.
  The history of a repository that was specialised before it was made generic still contains the old
  files, so publish a public copy from a fresh `git init` of the cleaned tree (one initial commit),
  never by pushing the old branches.
- **Use someone else's layer:** clone it into `layers/<name>/`, then `./install.sh --layers <name>`
  (add it to your existing list to keep the others).

## Worked example

A team layer called `acme` that adds a rule, a command and a hook.

```bash
cd ~/projects/claude-code-kit
cp -r layers/example layers/acme
```

`layers/acme/layer.json`:

```json
{
  "name": "acme",
  "description": "Acme team conventions: commit style, a release checklist, a Bash guard.",
  "requires": []
}
```

`layers/acme/rules/acme-git.md`:

```markdown
# Acme commit style

Commit messages use the form `[Feat] subject`, `[Fix] subject` or `[Chore] subject`.
```

`layers/acme/commands/release-checklist.md`:

```markdown
---
description: Walk through the Acme release checklist for the current repository
---

List the checks to run before tagging a release in this repository, run the ones that are safe
to run, and report the rest.
```

`layers/acme/hooks/hooks.json` and its script:

```json
{
  "description": "Acme hooks.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/layers/acme/hooks/scripts/no-prod-deploy.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# Refuse a deploy command aimed at production. Silent otherwise.
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception: print("")')
case "$cmd" in
  *"deploy --env prod"*) echo "refusing a production deploy from a session" >&2; exit 2 ;;
esac
exit 0
```

Optionally protect a folder: `layers/acme/protected-paths` containing `~/projects/acme-notes`.

Install, check, then back it up:

```bash
./install.sh --layers acme
./install.sh --check
cd layers/acme && git init && git add -A && git commit -m "feat: initial acme layer"
git remote add origin <your-private-remote>/acme-layer.git && git push -u origin HEAD
```

(Commit and push run from your own shell here; Claude Code only does that when you ask.)

## Migrating from the old layout

Earlier versions kept personal files in a `personal/` folder inside the kit and tracked the install
in a manifest named `~/.claude/.<name>-kit-manifest`. Both are replaced: move the folder's content into
`layers/<name>/` (the same sub-folders) and run `./install.sh --layers <name>`. The installer
migrates the manifest to `~/.claude/.claude-kit-manifest` by itself and keeps the old file as `.bak`.
