---
description: "Generate a commit message for all staged changes, written to commit-msg.txt"
argument-hint: "[optional: focus hint, e.g. \"emphasize CI changes\"]"
allowed-tools: Bash, Read, Write
model: haiku
---

Produce a git commit message for the currently staged changes and save it to a file for `git commit -F`.

## Step 1: Inspect staged state
Run and read: `git status --short`, `git diff --cached --stat`, `git diff --cached` (source of truth — every bullet must be grounded here), and `git log --oneline -n 10` (style reference).

If `git diff --cached` is empty, stop and tell the user: "No staged changes. Run `git add <files>` first."

## Step 2: Match this repo's commit style
**Read what `git log` actually shows and mirror it.** If the history shows no clear convention, default to Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`).
- Pick the prefix matching the dominant change; when torn, corrective beats additive.
- If a layer provides a commit-style rule (for example bracketed tags), follow it; the repo's history still wins.
- Ignore auto-generated merge titles (`Merged in ...`, `Merge pull request ...`) when inferring style.

## Step 3: Compose
Exact format (no code fences, no backticks, no emojis):
```
<prefix> <imperative summary, ≤70 chars>

- <change 1>
- <change 2>
```
- Title describes the *point* of the changeset, not a file list; imperative, present tense, no trailing period.
- One bullet per distinct meaningful change; group trivial related edits; omit the bullet block for a one-line change.
- **Each bullet is exactly one physical line in the file, however long — never hard-wrap it.** Start a new line only for the next bullet, or a genuine paragraph break (e.g. a blank line before a trailing footer). Do not wrap a bullet just because it looks long.
- No `Co-Authored-By` footer or other attribution trailer unless the user asks for it in `$ARGUMENTS`.

## Step 4: Save
Write the exact final message (nothing else) to `<repo-root>/commit-msg.txt` with the Write tool, overwriting prior content.

## Step 5: Report (≤3 lines)
Give the absolute path, the usage (`git commit -F commit-msg.txt`), and a note to gitignore `commit-msg.txt` if not already. Do not print the message body in chat.

Optional emphasis hint: $ARGUMENTS
