# Example layer

A layer is a folder with the same shape as the kit's core. `install.sh --layers a,b` installs the
core first, then each layer in order; a later layer wins when two files have the same name.

```
layers/<name>/
  layer.json          {"name", "description", "requires": []}  (requires = other layers it needs)
  rules/*.md          standing rules
  commands/*.md       slash commands
  agents/*.md         subagents
  skills/<skill>/SKILL.md
  hooks/hooks.json    hook groups, merged into ~/.claude/settings.json
  hooks/scripts/*.sh  the scripts those hooks run
  templates/          per-repo CLAUDE.md templates, if you use them
```

Make your own layer:

```bash
cp -r layers/example layers/mine && $EDITOR layers/mine/layer.json
./install.sh --layers mine          # remembered in ~/.claude/.claude-kit-layers
./install.sh --check
```

Keep a layer in its own git repository: the core ignores everything under `layers/` except
`layers/example`, so `git init` inside `layers/mine` gives you a private backup of your
specialisations without them ever landing in a shared copy of the kit.
