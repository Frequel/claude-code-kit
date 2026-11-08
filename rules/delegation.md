# Delegation and model choice

**When a task meets the criteria below, delegate to subagents
without asking the user first; when it does not, stay inline.** Decide by cost and speed, never by habit.
Delegation that adds cost without adding speed is a mistake, in both directions.

## Plan first when the task is not trivial

"Trivial" is about size and shape, not about the domain: code and infrastructure follow the same test.

- **Trivial — do it directly, no plan:** one step or a few obvious ones, a clear outcome, nothing to
  choose, easy to undo. A status check, a one-time schedule, a typo, a command the user dictated. A plan here
  costs more than the work, and there is nothing to split.
- **Not trivial — enter plan mode first** (`EnterPlanMode`), for code and for
  infrastructure or operations alike, when any holds: several steps that depend on each other; more
  than two or three files or resources; a choice between approaches; live state that is hard to undo
  (accounts, clusters, data); unclear scope; parts that could run in parallel.

Every plan includes a **who-does-what table** — phase, inline or agent, model, why — plus what needs the user's
input and how each risky step is undone. Once the user approves it, execute following the table. `/orchestrate`
produces exactly this on request.

## Delegate when at least one holds

- **Independent parts:** two or more pieces of work that share no files and do not wait on each other
  (two services, implementation and its tests, the same change in several repositories). Launch them
  **in one message** so they run at the same time.
- **Sweep:** the answer needs reading many files or repositories and only the conclusion matters. A
  read-only agent keeps the file dumps out of this context (`/fanout`, `Explore`). In a repository with a
  tokensave index, code research goes through tokensave instead, unless the user asks for the agent
  (`exploration.md`, "Precedence").
- **Mechanical bulk:** repetitive edits, renames, reformatting, link fixing, worklog writing. A Haiku
  agent does it for a fraction of the cost.
- **Specified implementation:** the plan is precise (files, behaviour, done-when). The stack's
  `*-service-dev` agent (Sonnet) implements while this session keeps the overview.
- **Second opinion:** a non-trivial plan or diff deserves `staff-reviewer` (Opus) in a fresh context.

## Stay inline when any holds

- The work is **interactive with the user**: console steps, decisions, answers only the user can give.
- It is **sequential**: each step needs the result of the previous one.
- It **touches live state** outside the repository (AWS accounts, clusters, DNS, production data):
  one session keeps its hand on it.
- It is **small**: one file, a few minutes, or briefing an agent would take longer than doing it.
- **The context is the expensive part**: what this session already knows would have to be re-derived
  by a cold agent.

Rule of thumb: parallel agents pay only when the parts are independent **and** each part is clearly
bigger than the brief it needs.

## Models

- Main session: a strong model while planning (plan mode), a faster one while executing, if your setup supports that split.
- Planning, architecture and review agents: Opus (`staff-reviewer`).
- Implementation and exploration agents: Sonnet (the default for subagents that declare no model).
- Mechanical agents: Haiku (`gate-runner`, worklog or note-writing agents, bulk edits). Pass `model` explicitly when
  the agent definition does not declare the one the job needs.
- Plain "where is X" searches, in a repository without a tokensave index: `Explore` with `model: haiku`. Keep Sonnet for any agent that has to reason across services or repositories.
- Mechanical commands already run on Haiku through their frontmatter (`/check`, `/commit-msg`,
  `/kit-doctor`).

## Subagents cannot start subagents

A Sonnet implementer cannot hand its mechanical part to Haiku later: the decision is made here, at plan
time. When splitting work, mark every mechanical part (docs and README tables, renames, the same change
propagated to several repositories, worklogs) as a Haiku part of its own. Chain instead of nesting: an
implementer finishes, `gate-runner` (Haiku) runs the checks, its failures go back to the same
implementer. The full build and test logs never reach the Sonnet or Opus context.

## How to brief and run them

- Each agent gets: the goal, the files or directories it owns, done-when, what must not break, and what
  to return (a short conclusion with `file:line` evidence, not dumps).
- Every brief repeats the hard rules: **no commits or pushes, no worktrees or second clones, no branch
  switching, stay inside your files.** Git is this session's job.
- Two agents never own the same file. Do not redo their work while they run; verify what they return
  before reporting it to the user.
- When you decide to delegate, tell the user in one line what goes to whom and why it is cheaper or faster.
  When the user asks for parallel work that fails the criteria, say why and propose the inline way.

## Explicit commands

- `/orchestrate <task>` — plan only, on Opus: the phases and the who-does-what table, then stop for the user's
  approval. It decides phase by phase whether an agent pays; it does not assume a team.
- `/team <task>` — any task as a team: plan, split, parallel agents, review, integrate.
- `/team-feature <feature>` — the same for a feature across files or services, with contract checks and the repo gate.
- `/fanout <question>` — a read-only question answered by parallel agents.
