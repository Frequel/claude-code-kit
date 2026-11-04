---
description: Build Docker image and run basic validation
allowed-tools: Bash(docker:*), Bash(ls:*), Read
---

Build and validate this repo's Docker image. `$ARGUMENTS` may override the local tag (default `<repo-name>:local`).

If the repo has no `Dockerfile`, say so and stop — it isn't a containerised service.

## Steps
1. Read the `Dockerfile` to confirm the base image, system deps, the copied paths, and the entrypoint/`CMD`.
2. Read the dependency manifest (`requirements.txt`/`Cargo.toml`/`go.mod`) to confirm runtime deps.
3. Build from the repo root (build context is `.`): `docker build -t "$(basename "$PWD"):local" .`.
4. Check size: `docker images "$(basename "$PWD"):local"`.
5. Sanity-check that the image and entrypoint load: `docker run --rm "$(basename "$PWD"):local" 2>&1 | head -30`. Without populated runtime config (DB/env/secrets) the process may fail fast — that's the expected validation path. Confirm the failure is a *config/connection* error (entrypoint started, app imported/linked), **not** an `ImportError`/missing-system-lib/bad-`CMD`/link error.
6. Optionally do a live boot with real config if the user provides one (`--env-file .env -p <port>:<port>`).
7. Report image size, observed startup behaviour, and any build warnings.
