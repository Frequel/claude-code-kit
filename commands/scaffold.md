---
description: "Scaffold a new service or module for this project"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

You are scaffolding new code for this repository, following its established patterns.

## Step 1: Requirements
If `$ARGUMENTS` is incomplete, ask what is being added and its purpose (a new external-integration client/service, a new endpoint/handler, a new data field/model change, a new env var/config knob, or a new library function/module).

## Step 2: Learn the conventions from the repo itself
1. Read `CLAUDE.md` for the layering and conventions.
2. **Open the closest existing example of the same kind and mirror it** — its structure, error-handling, logging, return contract, naming, and any banner/docstring convention. Do not invent a new pattern when one exists.

## Step 3: Generate
- Place new code in the layer `CLAUDE.md` prescribes (keep entrypoints/views thin; put external I/O behind the repo's service/client abstraction).
- Wire it where the repo expects (route table, module exports, etc.).
- New env var: add it to the repo's config example, read it the way the repo does, document it in `CLAUDE.md` if operationally significant, and mirror it into any test-bootstrap blocks the repo uses.
- Update the public-API doc/README/"available functions" list if the repo maintains one.

## Step 4: Verify
Run this repo's checks on the new files (`/check` or the stack defaults). Add tests mirroring the repo's existing test layout and run them. Rebuild the image if deps/`Dockerfile` changed.

Target: $ARGUMENTS
