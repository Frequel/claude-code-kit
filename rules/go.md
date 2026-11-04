---
paths:
  - "**/*.go"
  - "**/go.mod"
---

# Go

- The gate: `gofmt -l .` (any output is a failure), `go vet ./...`, `go test ./...`.
- Sibling services that share a layout and a filesystem convention: a path or permission change in one is a cross-repo change, so check the siblings. Keep any interface definition and its callers in sync.
- Errors are values: wrap with `%w` and handle at the boundary; do not log-and-continue in the middle of a handoff.
- If the service ships as a system package with a service unit, read the repository's packaging notes (or a packaging skill from your layers) before touching the packaging directory.
