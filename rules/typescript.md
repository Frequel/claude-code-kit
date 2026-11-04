---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/package.json"
---

# TypeScript

- Read `package.json` scripts before inventing a command: these repos do not share one convention. Use the repo's own `lint`, `build` and `test` scripts.
- Use the package manager the lockfile implies (`package-lock.json` → npm, `yarn.lock` → yarn, `pnpm-lock.yaml` → pnpm). Never switch a repo's lockfile as a side effect.
- Keep API types aligned with the server that produces them; a shape defined in the back end is a contract, not a suggestion.
- Do not add a dependency to solve something the repo already solves with what it has.
