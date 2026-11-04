---
name: build-check
description: "After editing source files in any repository, automatically run the stack's syntax check, linter (if installed), the matching unit tests, and a Docker build when packaging files changed — to catch broken syntax, lint violations, regressions, and Dockerfile drift before the user asks. Applies to Rust, Python, Go, and Bash scripts; detects the stack from the repo."
---

After editing application/source files, run the checks for the **detected stack** in sequence (read `CLAUDE.md` first — repo-specific commands and test runners override these defaults). Mirrors the repo's CI gate where one exists.

1. **Syntax** on changed files: Rust `cargo build`/`cargo check`; Python `python3 -m py_compile <files>`; Go `go build ./...`; Bash `bash -n <files>`. On failure, read the file, fix, re-check.
2. **Lint** (only if the tool is installed — guard with `command -v`): Rust `cargo clippy --all-targets --all-features`; Python `flake8`/`pylint` (respect the repo's config); Go `gofmt -l .` + `go vet ./...`; Bash `shellcheck <files>`. Fix real violations; don't reflow to satisfy a length the project doesn't enforce.
3. **Unit tests** for the touched area: run the repo's own runners if present (e.g. `python tests/run_<area>_tests.py`), else `cargo test` / `pytest` / `go test ./...`. If a new env var was introduced, update any test-bootstrap blocks the repo uses or the imports will fail.
4. **Docker build** only if `Dockerfile`, the dependency manifest, or a copied package changed: `docker build -t "$(basename "$PWD"):check" .`. On failure, fix the underlying cause (missing COPY path, a system lib, a manifest typo).
5. **YAML validity** if a CI config file was edited: `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('YAML is valid')" <file>`.

Report a brief summary: one line if all pass; otherwise list what was fixed.

## Gotchas

- Formatting is handled by the PostToolUse hook, so a `fmt --check` failure means the hook did not run (tool missing, or the file was written outside the Edit/Write tools) — investigate instead of reformatting by hand.
- `cargo clippy --all-targets` and `cargo test` compile different target sets; a green `cargo test` says nothing about clippy on test code.
- Skip a check only when the tool is genuinely absent, and say so explicitly in the summary. Silence reads as "it passed".
