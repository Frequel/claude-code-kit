# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

<!-- What the service does, and its public surface: endpoints / topics / interfaces, one line each. -->

## Commands

```bash
# Build / lint / test (mirrors the CI gate)
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --tests
cargo build --release

# Full suite including container-backed integration + e2e
# local  (process + container per test, best output):
cargo nextest run --features testcontainers --run-ignored all
# CI     (shared container per binary, single-threaded):
cargo test --features testcontainers --tests -- --include-ignored --test-threads=1

# Run locally
docker compose up --build
cargo run                 # needs the env vars listed below
```

<!-- Delete the testcontainers block if this crate has no database tier. -->

## Layout

<!-- Where the crate really is (not every repo has a root Cargo.toml), what is generated
     (OpenAPI scaffold) versus hand-written, and which module owns external I/O. -->

## Environment

| Variable | Purpose | Where it is set |
|---|---|---|

## Contracts (do not break silently)

<!-- Topics, schemas, tables owned elsewhere, installed paths. Name the repo on the other side. -->

## CI and packaging

<!-- Pipeline file, image and/or package, which registries. Link to shared release documentation
     rather than restating common machinery. -->

## Gotchas
