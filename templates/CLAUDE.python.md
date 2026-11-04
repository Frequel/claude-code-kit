# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

<!-- What the service does and its public surface (views/endpoints, consumers, jobs). -->

## Commands

```bash
# Syntax / lint / test — verified to run
python3 -m py_compile $(git ls-files '*.py')
# <the repo's real linter: ruff | flake8 | pylint>
# <the repo's real test runner: python tests/run_*.py | pytest>
```

## Layout

<!-- Apps/modules and what each owns. Name the layer used for external I/O. -->

## Environment

| Variable | Purpose | Read at import time? | Where it is set |
|---|---|---|---|

<!-- "Read at import time" matters: those turn a missing value into a startup crash. -->

## Data

<!-- Which tables/collections this service OWNS and which it only reads.
     Never migrate a table owned elsewhere. -->

## Contracts (do not break silently)

## CI and release

## Gotchas
