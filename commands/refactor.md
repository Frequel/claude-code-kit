---
description: "Restructure or improve existing code safely"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion
---

You are refactoring code in this repository. Refactoring changes structure **without** changing behaviour.

## Step 1: Scope
If `$ARGUMENTS` is empty, ask what kind of refactor (extract function, move logic into the orchestration layer, reduce duplication, simplify/flatten, improve testability, or custom) and which file(s).

## Step 2: Analyse before changing
1. Read `CLAUDE.md` for architectural constraints (layering, managed-vs-unmanaged data, contracts).
2. Read all affected files; map callers with Grep across the whole repo, including tests.
3. List the implicit contracts that MUST survive: public routes/interfaces, message/topic shapes, object-key/on-disk layouts, env-var names, and return contracts (tuples/`Result`/bool).
4. State the plan before touching code.

## Step 3: Apply
- **One refactor at a time** — don't combine changes.
- **Preserve behaviour** — same inputs/outputs/side effects.
- **Update every reference** — including imports and tests that name the moved symbol.
- **Minimal diff.**

## Step 4: Verify
Run this repo's checks on every touched file (`/check` or the stack defaults) and the relevant test runner(s). Rebuild the image if deps/`Dockerfile` changed. Show a summary of what changed.

Target: $ARGUMENTS
