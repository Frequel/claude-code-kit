---
description: Plan a task on Opus as phases with a who-does-what table (inline, Sonnet or Haiku agent, review), then stop for approval
argument-hint: "<the task, e.g. \"migrate the service to the new queue and update its deployment\">"
model: opus
---

Plan this task, do not execute it yet: $ARGUMENTS

This turn is planning only, on Opus. Read what you need (repository `CLAUDE.md` files, runbooks, the
notes the session-start hook pointed to, the code), but change nothing: no edits, no commands with
side effects, no cloud or cluster calls that write. Follow `rules/delegation.md`.

## 1. Triage
If the task is trivial (one step or a few obvious ones, nothing to choose, easy to undo), say so in one
line and stop: it will be done directly when the user confirms, without a plan.

## 2. Phases
Split the task into phases in execution order. For each: what it produces, what it depends on, and
whether it touches live state (accounts, clusters, data, DNS) or needs the user at a console.

## 3. Who does what
One table, one row per phase:

| Phase | Done by | Model | Why this choice |
|---|---|---|---|

- **Inline (main session)** for interactive, sequential, small or live-state work, and where this
  session's context is the expensive part.
- **Agents in parallel** only for independent parts, each clearly bigger than its brief: the stack's
  `*-service-dev` (Sonnet) to implement, a domain-expert or cross-repo agent from your layers (Sonnet) if one exists to investigate across services, `Explore` with `model: haiku` for plain searches.
- **Haiku** for mechanical parts, assigned now because a Sonnet agent cannot delegate later: `gate-runner`
  for every check (format, lint, build, tests, `terraform validate`), a note-writing agent from your layers for the worklog if one exists,
  `general-purpose` with `model: haiku` for bulk edits and docs.
- **Review:** `staff-reviewer` (Opus) on the plan if it is risky, and on the final diff.
Mark which rows run in parallel, and say where a team would cost more than it returns.

## 4. Before the user approves
- What the user must decide or provide, and when in the sequence.
- Each risky step and how it is undone; anything irreversible stated as such.
- Rough effort per phase and the overall order.

Then stop and wait. After the user approves (or amends), execute following the table: the main session runs the
inline rows; launch the parallel rows in one message; no commits or pushes unless the user asks.
