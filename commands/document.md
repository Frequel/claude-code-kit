---
description: "Generate or update documentation for this project"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

You are generating or updating documentation for this repository.

## Step 1: Scope
If `$ARGUMENTS` isn't specific, ask which: in-code doc comments (docstrings / `///` rustdoc / function banners), architecture docs (`CLAUDE.md`/`README.md`), operational docs (env vars, public API/contract, on-disk/object-key layouts), an API spec (e.g. a swagger/openapi file), or a full pass.

## Step 2: Analyse
1. Read `CLAUDE.md` and `README.md` for current architecture.
2. Read the source for the area being documented and verify the documented flow matches reality.
3. Cross-check the config example against actual env reads, and the dependency manifest against actual imports — flag any drift.
4. If an API spec exists, reconcile its paths/verbs against the routes actually wired in code.

## Step 3: Write
- Use the repo's existing doc-comment convention (PEP 257 docstrings, rustdoc, or the shell banner style) — one-line summary plus a paragraph for non-trivial behaviour. Never add a comment that just restates the name.
- Document the expected shape of inputs at boundaries (request bodies, message/topic formats, key layouts).
- When updating `CLAUDE.md`/`README.md`, preserve the existing structure and writing style; update only what's stale.
- For env-var docs, list each: name, required/optional, default, purpose.

## Step 4: Verify
Run this repo's checks on touched files (`/check` or the stack defaults) to confirm doc comments didn't break syntax.
