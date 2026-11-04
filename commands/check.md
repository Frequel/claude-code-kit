---
description: Run lint, syntax, and build checks for the project (auto-detects stack)
allowed-tools: Bash, Read, Glob
model: haiku
---

Run this repo's quality checks in sequence, stopping at the first failure. Report each step's result.

First read `CLAUDE.md` — if it documents specific check commands or test runners, those take precedence over the defaults below.

## 1. Detect the stack
Inspect the repo root: `Cargo.toml`→Rust, `manage.py`/`requirements.txt`/`pyproject.toml`/`*.py`→Python, `go.mod`→Go, only `*.sh`→Bash library. A repo may be more than one.

## 2. YAML validity (if a CI config file such as `.gitlab-ci.yml` or a pipelines YAML exists and was touched)
`python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('YAML is valid')" <file>`

## 3. Stack checks (run the matching block; mirror the repo's CI gate)
**Rust**
- `cargo fmt --all -- --check`
- `cargo clippy --all-targets --all-features`
- `cargo test` (the lib/bin tests the repo has)

**Python**
- Syntax: `find . -path ./.venv -prune -o -name '*.py' -print | xargs -r python3 -m py_compile`
- Lint: `flake8` (or `pylint`) on the source dirs **if installed** — skip with a note otherwise. Respect `.flake8`/config.
- Tests: run the repo's self-contained runners if present (`python tests/run_*.py`), otherwise `pytest` if a `tests/` dir exists.

**Go**
- `gofmt -l .` (fail if any file listed), `go vet ./...`, `go test ./...`

**Bash library**
- `shellcheck` every `*.sh` (skip with a note if not installed), `bash -n` every `*.sh`.

## 4. Docker build (only if `Dockerfile`/deps/a copied package changed)
`docker build -t "$(basename "$PWD"):check" .`

For each step: pass → report and continue; fail → show the error and **stop**. End with a one-line summary.
