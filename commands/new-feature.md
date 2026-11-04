---
description: Run the complete multi-role feature workflow
---

Execute the full feature development lifecycle for: $ARGUMENTS

Read `CLAUDE.md` first; every phase adapts to this repo's stack, layering, and constraints.

## Phase 1: Architecture
Adopt the `/architect` role. Decide which existing layer the feature belongs in. Produce `Plan.md` updates and any ADRs. **Present the design and STOP for approval.**

## Phase 2: Implementation (after approval)
Adopt the `/dev` role. Implement following the repo's established patterns. After each meaningful change, run this repo's checks (`/check` or the stack defaults) and rebuild the image if deps/`Dockerfile` changed.

## Phase 3: Review
Adopt the `/review` role on everything written in Phase 2. If there are BLOCKING findings, switch back to `/dev`, fix, and re-review.

## Phase 4: Packaging & Pipeline
Adopt a packaging/CI role (the `/devops` command if your layers provide one; otherwise do it inline). If the `Dockerfile`/deps changed, confirm the image still builds and boots. Confirm whether any CI configuration change is needed.

## Phase 5: Summary
State what was built, trade-offs made, and delivery status (branch, build status). Work on a `feature/*` branch throughout; never commit to `master`/`main`/`develop`.
