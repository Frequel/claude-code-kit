# Exploring code without burning context

Order of preference when you need to understand code you have not read yet:

1. **tokensave MCP tools** (`tokensave_context` first, then `search`, `callers`, `callees`, `impact`, `node`, `files`, `affected`). They return the relevant source sections instead of whole files. Pass `seen_node_ids` from each response to the next call's `exclude_node_ids`.
2. **Direct reads** of a file you can already name.
3. **A read-only subagent**, when the answer needs a sweep over many files and you only want the conclusion.

**Precedence.** `rules/tokensave.md` is written and rewritten by tokensave itself, so this kit never edits it; where
it and this file or `delegation.md` disagree, it wins for code exploration in a repository that has a `.tokensave/`
index. Concretely: in an indexed repository no `Explore` or other research subagent is started for code questions
unless the user asks for one (an explicit `/fanout` is that request); in a repository without an index, or for
non-code research, the subagent in step 3 is fine.

Fallbacks, because the first option is not always available:

- `tokensave_status` fails or the MCP server is not connected → say so once, then use direct reads and grep. Do not stall.
- The repo has no `.tokensave/` index → either run `tokensave init` in the repo root, or proceed with direct reads. Only some repositories are indexed.
- A structural question the tools do not answer natively → query `.tokensave/tokensave.db` directly with SQL (tables: `nodes`, `edges`, `files`).

If a tokensave tool or extractor is missing something it should answer natively, say so — it is worth an issue at https://github.com/aovestdipaperino/tokensave (strip any proprietary code from the report first).
