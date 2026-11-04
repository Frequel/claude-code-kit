---
name: debug
description: "Diagnose and troubleshoot errors, exceptions, and unexpected behavior in any repository (Rust, Python, Go, or Bash). Use when the user reports an error, shares a traceback/panic, hits an HTTP 4xx/5xx, sees a container crash or build failure, or describes unexpected behavior. Triggers on 'I'm getting an error', 'this crashes', 'why is this failing', 'help me debug', '500 error', 'docker build fails', 'tests won't import', or when the user pastes a traceback/log."
---

When the user reports an issue, classify it and investigate systematically. Read `CLAUDE.md` first for the repo's data/request flow and known caveats, then detect the stack and read the file(s) named in the error.

## Classification (pick what fits the stack)
- **Import / startup / build** — config read at load time crashing on a missing var; missing dependency; a system-lib/compile/link error.
- **Framework / routing** — request not matched, serializer/validation, status mapping, CORS/allowed-hosts.
- **Data layer** — SQL/ORM schema drift (often a shared table owned by another service), NoSQL lookup returning empty, connection/credentials.
- **External I/O** — HTTP clients that return a non-2xx as a *value*, not an exception; object-store endpoint/key/permission errors; missing timeouts causing hangs.
- **Domain logic** — message/topic parsing (wrong part-count, bad id type, disallowed enum value).
- **Auth** — token/claim handling and provider differences.
- **Pipeline / Docker** — build fails, image not pushed, wrong region, missing CI variable.

## Strategy
Trace the path end to end through the layers `CLAUDE.md` documents. Inspect the error-handling around the failure point — broad handlers often log-and-return a code, hiding the real cause. Check `git diff` and `git log --oneline -20` if the issue appeared after a change.

## Output
Present **root cause**, **evidence** (file:line), and **impact**. If asked to fix, make the minimal change, then run the repo's checks (`/check` or the stack defaults) and the relevant test runner.

## Gotchas

- HTTP clients often return a non-2xx **as a value**, not as an error. A broad `except`/`match` that logs and returns a code hides the real cause — read the error handling before believing the log.
- A failure that appeared "out of nowhere" on a deployed machine is usually a package or dependency version skew, not a code bug: check which version that machine actually runs.
- Reproduce before fixing. If the repo has a container-backed test tier, write the failing test there first.
