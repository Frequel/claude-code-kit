---
description: "Diagnose and fix errors, exceptions, or unexpected behavior"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion
---

You are diagnosing an issue in this repository. Work systematically.

## Step 1: Gather the problem
If `$ARGUMENTS` doesn't describe the issue, ask for: the error/symptom (traceback, log line, HTTP status, or unexpected behaviour), the context (which endpoint/component, when, after what change), and the reproduction (trigger, inputs, config). If a traceback is already pasted, skip the questions and analyse.

## Step 2: Orient
Read `CLAUDE.md` for the request/data flow and known caveats. Detect the stack and read the file(s) named in the traceback.

## Step 3: Classify (pick what fits the stack)
- **Import/startup/build** — config read at load time when a var is missing; missing dependency; system-lib/compile error.
- **Framework/routing** — request not matched, serialization/validation, status mapping.
- **Data layer** — SQL/ORM schema drift (especially tables owned by another service), NoSQL lookup returning empty, connection/credentials.
- **External I/O** — HTTP clients returning a non-2xx as a *value* (not an exception); object-store endpoint/key/permission errors; timeouts.
- **Domain logic** — message/topic parsing, id-type confusion, disallowed enum values.
- **Auth** — token/claim handling, provider differences.
- **Pipeline/Docker** — build fails, image not pushed, wrong region, missing pipeline var.

## Step 4: Investigate
Trace the path end to end through the layers `CLAUDE.md` documents. Inspect the `try/except`/`Result` handling around the failure — broad handlers here often log-and-return a code, hiding the real cause. Check `git log --oneline -20` and `git diff` if the issue is new.

## Step 5: Diagnose
Present **root cause**, **evidence** (file:line), and **impact**.

## Step 6: Fix (if requested)
Make the minimal change, then run this repo's checks for the touched files (`/check` or the stack defaults), and the relevant test runner. Rebuild the image if deps/`Dockerfile` changed. Explain what changed and why. If the fix needs an architectural change, present options and let the user decide.

Issue to debug: $ARGUMENTS
