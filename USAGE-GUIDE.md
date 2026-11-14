# How to use this kit

The practical how-to for the kit's **core** commands, skills, agents and hooks. Anything that belongs
to a layer (your team's or your own workflows) is documented in that layer's own `USAGE-GUIDE.md`.

---

## First-time setup

### What this is

A versioned single source of truth for Claude Code configuration across many repositories:

- **One kit**, installed as a plugin or symlinked into `~/.claude`.
- **Lazy loading**: stack rules load only when you touch matching files.
- **Hooks enforce**: formatting runs automatically, commits to protected branches are blocked, the
  configuration protects itself from deletion.
- **Parallelism where it pays**: `rules/delegation.md` decides when subagents help; `/team`,
  `/team-feature` and `/fanout` run them in your checkout.
- **Per-repo guidance**: every repository gets a `CLAUDE.md` with commands you have tested.

### Install

```bash
cd ~/projects/claude-code-kit
./install.sh --user                 # core only
./install.sh --layers mine          # core plus your layer(s)
```

Symlinks go from `~/.claude/{commands,skills,agents,rules}` to the kit, so `git pull` updates every
session. Nothing outside the manifest (`~/.claude/.claude-kit-manifest`) is touched. Links are
relative, so the same install works on the host and in dev containers that bind-mount `~/.claude`,
provided `~/.claude` and the kit keep the same relative position on both sides.

Plugin mode instead:

```
/plugin marketplace add ~/projects/claude-code-kit
/plugin install claude-code-kit@claude-code-kit
```

It carries the core's commands, skills, agents and hooks. Rules and layers still need
`./install.sh --rules-only` / `--layers`.

After installing, restart Claude Code and run `/kit-doctor`. It should report no problems; if not,
the output names the file or permission to look at.

---

## Day to day

### Opening a session in a repository

The `SessionStart` hook runs `orient.sh` (for repositories under `~/projects`, or
`CLAUDE_KIT_PROJECTS_DIR`) and prints the repository, the branch and the detected stack, and tells
you when there is no `CLAUDE.md`:

```
## Repo orientation
my-service — branch `feature/retry` — rust tokensave-indexed
```

A layer can add more lines with its own `SessionStart` hook. Then read the repo's `CLAUDE.md`
before writing anything.

### Reading CLAUDE.md

| Section | What is in it |
|---|---|
| **Project** | What the repo owns, and what is surprising about it |
| **Commands** | Every command that runs in the repo, tested with exit 0 |
| **Architecture** | The high-level structure, or a pointer to `docs/` |
| **Contracts** | What this repo owns that others consume |
| **Gotchas** | Why clippy sometimes fails, why a test is `#[ignore]`, what you cannot do |
| **Verification** | What "working" means for this repo |

### What loads when you write a prompt

- **Always:** `rules/git.md`, `rules/exploration.md`, `rules/config-safety.md`, `rules/delegation.md`
  (plus any always-on rule from your layers).
- **On Rust files:** `rules/rust.md`. **Go:** `rules/go.md`. **Python:** `rules/python.md`.
  **TypeScript:** `rules/typescript.md`.

On every real prompt the `delegation-check` hook also reminds the model to classify the task (trivial: do it;
not trivial: plan mode with a who-does-what table, then delegate what pays). You never have to ask for
the split. A slash command or a very short answer skips the reminder.

You do not re-read these, so a prompt can be short and specific:

```
Add tests for the retry loop in export_jobs, covering timeouts and network errors.
```

### Commands

| Command | What it does |
|---|---|
| `/check` | Runs the gate: format, lint, build and tests for the detected stack |
| `/commit-msg` | Writes a commit message for the staged changes to `commit-msg.txt` |
| `/go` | Finishes the work end to end: gate, simplify, review, commit, PR (each step on your say-so) |
| `/architect` | Adopt the software-architect role to design a component |
| `/dev` | Adopt the developer role to implement a feature |
| `/review` | Adopt the code-review role (adversarial) |
| `/refactor` | Restructure existing code safely |
| `/scaffold` | Scaffold a new service or module |
| `/document` | Generate or update documentation |
| `/docker-build` | Build the Docker image and run basic validation |
| `/code_diagnosis` | Diagnose an error, exception or unexpected behaviour |
| `/new-feature` | The complete multi-role feature workflow |
| `/orchestrate` | Plan only, on Opus: phases and a who-does-what table, then stop for approval |
| `/team` | Any task as a team: plan, parallel agents on disjoint files, review, integrate (inline when a team would not pay) |
| `/team-feature` | A feature as a team in one checkout, with contract checks and the repo gate |
| `/fanout` | Answer a broad question with parallel read-only agents |
| `/kit-doctor` | Health check of the Claude Code configuration |

Skills are not typed: `build-check` runs the syntax check, linter and matching tests after you edit
code, and `debug` is used when you report an error or paste a traceback.

### Subagents

| Agent | Model | Use |
|---|---|---|
| `staff-reviewer` | Opus | Adversarial second opinion on a plan or a diff, in a fresh context |
| `rust-service-dev`, `go-service-dev`, `python-service-dev` | Sonnet | Implement a scoped, already specified change and leave the repo green |
| `test-suite-architect` | Sonnet | Build or audit the test suite of a repository |
| `gate-runner` | Haiku | Run the gate and return only the failures with `file:line` |

### What happens when you edit a file

After an edit to a `.rs`, `.go`, `.py`, `.ts` or `.sh` file, the `PostToolUse` hook formats it:
`rustfmt`, `gofmt`, `ruff format`, `prettier`, `shfmt`. A formatter that is not installed is
skipped silently, so you never format by hand and CI never fails on formatting.

### When you commit or push

The `guard` hook parses the command and looks at the repository it **actually acts on**: `cd repo &&
git commit` and `git -C repo commit` are checked against `repo`, not against where the session
started. It:

- refuses `git commit` and `git push` on `master`, `main` or `develop`;
- refuses force pushes (`-f`, `--force`, `+refspec`); `--force-with-lease` is allowed;
- allows everything else, and ignores the words inside quotes, heredocs and `echo`.

Work on `feature/*`, `bugfix/*` or `hotfix/*`:

```bash
git switch -c feature/my-change --no-track origin/develop
git push -u origin HEAD
```

`--no-track` keeps the new branch from tracking the protected branch it was cut from.

### The configuration protects itself

The `protect-config` hook refuses commands that delete or move the Claude config directory's
`commands`, `rules`, `agents`, `skills`, `hooks`, `settings`, manifests, `plugins` and memories,
the kit root, its top-level folders, layer folders and `.git`, and any folder listed in a
`protected-paths` file (in `~/.claude` or in a layer in use). Editing single files inside the kit is
allowed. Before a change it snapshots the configuration through `scripts/backup-config.sh` (at most
hourly) and reminds you once per session. Broken links are fixed by `./install.sh --check` then
`./install.sh`, never by deleting folders.

---

## Implementing a feature

### Small change (one repo, one concern)

1. Open the repo and read the orientation line and the `CLAUDE.md`.
2. Write a specific prompt; the rules are already loaded.
3. `/dev` to adopt the developer role (optional).
4. `/check` to confirm the gate passes.
5. `/go` to finish: simplify, review, commit, PR.

### Larger change (several services)

```
/team-feature Add request tracing across API boundaries
```

This plans in plan mode (Opus under `opusplan`) and splits the work into parts that own disjoint
files; works on one feature branch in your checkout (no worktrees, no clones); runs one implementer
per part in parallel; has `staff-reviewer` check each diff; and runs the repo gate on the combined
result. Nothing is committed until you ask. `rules/delegation.md` decides whether a team pays at all.

### Understanding a broad area

```
/fanout How does a request flow from the API to the worker?
```

Read-only agents search in parallel and return a synthesised answer without file dumps in your context.

---

## Fixing a bug

1. Open the repo and read its Gotchas.
2. Use `/fanout` if the bug crosses repositories.
3. Paste the error or traceback: the `debug` skill (or `/code_diagnosis`) takes over.
4. `/review` before committing if the change touches a contract.

---

## Adding a repository to the kit

```bash
cd ~/projects/claude-code-kit
./propagate.sh <repo>             # dry run
./propagate.sh --apply <repo>     # removes forked copies of kit commands, adds a CLAUDE.md skeleton
```

The skeleton comes from `templates/` (base plus the detected stack). Then fill it in:

1. **Project**: read the README, the Dockerfile or manifest, and state what it owns.
2. **Commands**: run each one in the real repo; document failures honestly (missing Docker, credentials).
3. **Architecture**: a short overview or a pointer to `docs/`.
4. **Contracts**: tables, endpoints, topics or file layouts other code depends on.
5. **Gotchas**: what surprised you, what cannot be changed, what is async but looks sync.
6. **Verification**: what "working" means.

Then `/check` and `/commit-msg`, review the message, and commit it yourself.

---

## Troubleshooting

### A command, rule or skill works on one side only (host or container)

An absolute symlink or hook path resolves on one side only. The installer writes relative links and
`$HOME` hooks. Check, then reinstall; never delete `~/.claude/commands` or any other folder:

```bash
cd ~/projects/claude-code-kit
./install.sh --check      # BROKEN / ABSOLUTE entries are the ones to fix
./install.sh --user
```

### The format hook does not run

The formatter may not be installed (the hook skips silently), the extension may not be handled, or
the hook may lack permission. Run the formatter by hand to see the real error (`cargo fmt`,
`gofmt -l .`, `python -m ruff format .`).

### The guard refuses my commit or push

You are on `master`, `main` or `develop`, or the push is a force push. Switch to a feature branch, or
use `--force-with-lease`.

### tokensave

`tokensave CONNECTION_CLOSED` at session start means the code-graph server could not connect: the
directory is not an indexed project, or the binary is not on the PATH. Index a repository with
`tokensave init` in its root, or fall back to direct reads and `/fanout`.

Known issue: tokensave appends a broken `Stop` hook to `~/.claude/settings.json` each time its CLI
runs, unless a `Stop` hook containing `tokensave hook-stop` exists. Add
`command -v tokensave >/dev/null 2>&1 && tokensave hook-stop || true` as a `Stop` command and delete
the broken entries. Register the MCP server with
`claude mcp add --scope user tokensave -- tokensave serve`, and never run `tokensave doctor`,
`install` or `upgrade` on a shared config. Never run `rtk init -g`.

### A layer is missing

`./install.sh --list-layers` shows what is in use; the selection lives in
`~/.claude/.claude-kit-layers`. See `docs/layers.md`.

---

## If something breaks

```
/kit-doctor
```

It checks MCP servers, kit integrity, hooks, duplicates and every repository's `CLAUDE.md`. Most
problems are a missing permission, a stray conflicting file (reported, never touched) or a link
that resolved to the wrong place (rerun `./install.sh`). `bash tests/hooks.sh` verifies the hooks
themselves.

## The three rules that matter most

1. **Run every command first.** Each documented command was tested; if it fails, read the Gotchas.
2. **Commit to feature branches.** Protected branches are enforced by the guard hook.
3. **Keep the gate green.** `/check` before a commit, `/go` after the code.
