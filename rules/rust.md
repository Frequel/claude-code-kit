---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust

- Edition 2024. Follow the Rust API Guidelines. Every public function and type carries a doc comment.
- `thiserror` for library errors, `anyhow` for binary-level propagation. Do not invent a third error strategy in a repo that already picked one.
- The gate before any commit: `cargo fmt --all -- --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`. Formatting is applied automatically by the PostToolUse hook, so a `fmt --check` failure means the hook did not run.
- Every new function gets at least one unit test; `#[cfg(test)]` modules for unit tests, `tests/` at the crate root for integration tests.
- Prefer composition over inheritance-shaped trait towers; prefer explicit over clever.
- Several services are generated from an OpenAPI spec (`rust-axum` scaffold): the generated half is not hand-edited — the binary wires a concrete implementation into it. Check which half you are in before changing a signature.
- Not every repo has a root `Cargo.toml` (`m2m-tunnel`, `test-catalog-manager`): find the real crate before running cargo.
