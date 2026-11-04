# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

<!-- What this service does, and which sibling services it hands off to. -->

## Commands

```bash
gofmt -l .          # any output is a failure
go vet ./...
go test ./...
go build ./cmd/...
```

## Layout

`cmd/` entry points · `internal/` private packages · `pkg/` reusable · `test-client/` manual harness · `debian/` packaging.
<!-- Name the package that owns the external interface (RPC, IPC or HTTP) and the one that owns filesystem layout. -->

## Contracts (do not break silently)

<!-- Interface names and signatures, filesystem paths shared with sibling services,
     and the repo on the other side of each. -->

## CI and packaging

<!-- Pipeline file, package or image name, service unit if any. -->

## Gotchas
