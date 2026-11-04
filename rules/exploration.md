# Exploring code without burning context

Order of preference when you need to understand code you have not read yet:

1. **tokensave MCP tools** (`tokensave_context` first, then `search`, `callers`, `callees`, `impact`, `node`, `files`, `affected`). They return the relevant source sections instead of whole files. Pass `seen_node_ids` from each response to the next call's `exclude_node_ids`.
2. **Direct reads** of a file you can already name.
3. **A read-only subagent**, when the answer needs a sweep over many files and you only want the conclusion.

Fallbacks, because the first option is not always available:

- `tokensave_status` fails or the MCP server is not connected → say so once, then use direct reads and grep. Do not stall.
- The repo has no `.tokensave/` index → either run `tokensave init` in the repo root, or proceed with direct reads. Only 17 of the repositories are indexed.
- A structural question the tools do not answer natively → query `.tokensave/tokensave.db` directly with SQL (tables: `nodes`, `edges`, `files`).

If a tokensave tool or extractor is missing something it should answer natively, say so — it is worth an issue at https://github.com/aovestdipaperino/tokensave (strip any proprietary code from the report first).
