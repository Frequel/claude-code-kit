---
paths:
  - "**/*.py"
  - "**/requirements*.txt"
  - "**/pyproject.toml"
---

# Python

- The gate: syntax (`python3 -m py_compile`), lint (`ruff`/`flake8`/`pylint` — whichever the repo configures, guard with `command -v`), then tests.
- Run the repo's own test runner when it has one (`python tests/run_*.py`); fall back to `pytest` only when there is none. A repo-specific runner usually bootstraps env vars that `pytest` alone will not set.
- A new environment variable means updating `.env.example`, the CI variables **and** any test-bootstrap block, or imports fail before a single test runs.
- Django and similar services: a config value read at import time turns a missing variable into a startup crash, not a graceful error. Check settings before adding one.
- Never migrate a database table your service does not own; tables can be shared with another service.
