# CLAUDE.md

Guidance for Claude Code when working in this repository.

<!--
  HOW TO USE THIS TEMPLATE
  - Target 80-150 lines. Under 60 usually means the Commands section is a lie.
  - Every command below must have been RUN and exited 0 before it is written here.
  - Say what is NOT obvious from the code. Do not restate the directory listing.
  - Stack conventions live in ~/.claude/rules/<stack>.md — do not repeat them here.
  - Delete every section that has nothing true to say.
-->

## Project

One paragraph: what this service does, for whom, and where it sits in the larger system.
Then the public surface — endpoints, message topics, IPC interfaces, CLI entry points — with one line each.

## Commands

```bash
# Build / lint / test — these mirror the CI gate and are verified to run
```

If the full test suite needs containers, credentials or a database, say exactly how to get them and which command CI uses instead.

## Architecture

The layering, and which module owns which responsibility. Name the abstraction used for external I/O (client / gateway / service layer) — it must not be bypassed.
An ASCII diagram beats three paragraphs when the flow crosses processes.

## Contracts (do not break silently)

Anything another repository depends on: message and topic shapes, schemas, tables owned elsewhere, object-key layouts, installed paths, env-var names. For each, name the repository on the other side.

## CI and release

How this repo builds and ships: pipeline file, artifact (image / package), where it is published, and what triggers it. Point at the shared release documentation rather than restating common machinery.

## Gotchas

The things that have actually cost time here: the surprising failure, the test that lies, the config read at import time, the command that must be run from a subdirectory. Add to this list every time something bites.
