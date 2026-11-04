---
description: Build a feature with a parallel agent team in the current checkout (disjoint files, no worktrees)
---

Deliver this feature with a team instead of alone: $ARGUMENTS

Use this when the work splits into parts that can progress independently (two services, implementation
plus tests, a change plus its pipeline). If the work is one small edit in one file, say so and just do it
— a team costs more than it returns. The decision rules are in `rules/delegation.md`.

## 1. Plan (main session, plan mode, do not delegate)
Read the repo's `CLAUDE.md`. Establish what is being built and, critically, **how the work splits**: each
part owns its files, so two agents never edit the same file. Write the split down — part name, files
owned, done-when, agent and model. Mechanical parts (docs, tables, renames, the same edit in several
repositories) become Haiku parts now: a Sonnet implementer cannot delegate them later.
If the feature crosses a contract (a message format, an interface, a schema, a shared table, an installed path), find every repository affected **first** (use a cross-repo impact agent if your layers provide one, otherwise do it inline) and fold the rollout order into the plan.
Have `staff-reviewer` review the plan before anything is implemented. Apply what it finds.

## 2. Prepare the checkout (main session)
Create **one** feature branch in the user's checkout (`feature/<slug>`, or `bugfix/<slug>`), carrying any
uncommitted changes only after asking the user what to do with them. All parts work in this same
checkout on disjoint files. **No worktrees, no clones, no `isolation: worktree`** (`rules/git.md`). Parts in
different repositories simply work in their own repository.

## 3. Implement in parallel
Launch one implementer per part **in a single message** so they run concurrently: `rust-service-dev`,
`go-service-dev` or `python-service-dev` by stack, `test-suite-architect` for tests, and an agent from your layers for
pipelines if one exists. Give each agent: the files it owns, the done-when, the contracts it must not break, and the
hard rules — **no git commands that change state (no commit, branch, checkout, stash, reset), stay inside
your files, run only your part's tests.** While they work, do not duplicate their work.

## 4. Verify and review
When each part reports back, run `gate-runner` (Haiku) on its scope; its failures go back to the same
implementer until it passes. Then run `staff-reviewer` on its diff (`git diff -- <its files>`). Blocking findings
go back to the same implementer (continue that agent, do not start a fresh one). Repeat until clean.

## 5. Integrate
Run `gate-runner` on the whole repository (the full gate) on the combined working tree — the parts passed separately, which
proves nothing about them together. Fix integration failures in the main session.

## 6. Close
Report: what each part built, what the reviewer caught, the gate's result, the branch name, and what
would be committed (one commit per logical part). Then write the worklog (if an agent for this exists in your installed layers, delegate to it; otherwise skip).

**Never** commit, merge or push unless the user asks; never touch `master`, `main` or `develop`.
