---
description: Do any task with a team of parallel agents (Opus plans and reviews, Sonnet/Haiku execute) — only when it pays
---

Do this as a team: $ARGUMENTS

Follow `rules/delegation.md`. A team is worth it only when the work splits into independent parts, each
clearly bigger than its brief. If it does not, say so in one line and do it inline — a team costs more
than it returns.

## 1. Plan (this session, plan mode, do not delegate)
Establish the goal and split it into parts. For each part write: name, files or directories owned,
done-when, and the model it needs (Sonnet to implement or explore, Haiku for mechanical work, Opus only
for design or review). Two parts never own the same file. Work that depends on another part's result
waits for it: it is not a parallel part.
Subagents cannot start subagents, so mark mechanical parts (docs, tables, renames, the same edit in
several repositories) as Haiku parts **now**; a Sonnet agent cannot delegate them later.
For anything non-trivial, have `staff-reviewer` review the split before work starts.

## 2. Run in parallel
Launch every independent part **in one message**. Pick the agent per part: the stack's
`*-service-dev` for code, `test-suite-architect` for tests, an agent from your layers for pipelines and packaging or for investigation across services if one exists (otherwise do it inline), `Explore` with `model: haiku` for plain
searches, `general-purpose` with `model: haiku` for mechanical edits. Each brief carries the goal, the owned files, done-when, what must not break, what to
return, and the hard rules: **no commits or pushes, no worktrees or clones, no branch switching, stay
inside your files.** Never use worktree isolation.
While they run, do only the work no agent owns.

## 3. Review and integrate
Check each result against its done-when. For code, run `gate-runner` (Haiku) on each part as it
finishes and send its failures back to the same agent (continue it, do not start a fresh one), until it
passes. Then `staff-reviewer` on the combined diff and `gate-runner` once more on the integrated result:
parts that pass alone prove nothing together. The logs stay with `gate-runner`.

## 4. Report
What each part delivered, what the review caught, the gate result, and what was left out and why. Then
the worklog (if an agent for this exists in your installed layers, use it; otherwise skip). No commit or push unless the user asks.
