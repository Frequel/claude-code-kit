---
description: Finish the current work end to end — gate, simplify, review, commit, PR
allowed-tools: Bash, Read, Glob, Grep, Edit, Skill, Agent
---

Take what is in the working tree from "it seems to work" to "it is delivered". $ARGUMENTS may narrow the scope.

Run in order, stopping at the first failure and fixing it before continuing:

1. **Gate** — delegate to `gate-runner` (Haiku: it runs the repo's real commands from its `CLAUDE.md`
   and returns only the failures). Green or stop; fix the failures here and run it again.
2. **Simplify** — invoke the `simplify` skill on the changed code: reuse what the repo already has, drop what the change does not need. Re-run `gate-runner` afterwards.
3. **Review** — `staff-reviewer` on the diff. Fix blocking findings, re-run `gate-runner`.
4. **Branch** — confirm you are on `feature/*`, `bugfix/*` or `hotfix/*`. If you are on `master`, `main` or `develop`, create the branch and move the work; never commit there.
5. **Commit** — one commit per logical unit, in the repo's own style (`git log --oneline -n 10`). No AI attribution trailers.
6. **Pull request** — only if asked, or if the repo's workflow expects one. Push the branch and open it with a body that states what changed, what was verified, and what was deliberately left out.
7. **Worklog** — if an agent for this exists in your installed layers (for example a note-writing agent), delegate to it; otherwise skip it unless the repo asks for one.

Report the branch, the gate result, and anything you chose not to do.
