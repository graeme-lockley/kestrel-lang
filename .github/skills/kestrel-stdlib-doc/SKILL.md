---
name: kestrel-stdlib-doc
version: 1.0.0
description: >-
  Improve Kestrel stdlib/module documentation with practical examples: add
  module-level overview docs (`//!`), quick-start usage blocks, and clear
  per-function doc comments (`///`) that describe behavior, edge cases, and
  common usage patterns.
inputs:
  - module_path: "path to a .ks module (e.g. stdlib/kestrel/data/list.ks)"
outputs:
  - "adds or refreshes //! module docs and /// declaration docs in the target module"
  - "never modifies runtime behaviour"
allowed-tools: [read_file, list_dir, file_search, grep_search, replace_string_in_file, multi_replace_string_in_file, run_in_terminal]
forbids: ["git push", "git push --force", "git reset --hard", "rm -rf"]
---

# Kestrel documentation workflow

Use this skill when you are documenting Kestrel source modules (`.ks`) and want
high-signal docs that are useful in both source files and `kestrel doc` output.

## Inputs

- **module_path** — a `.ks` module to document.

## Outputs / Side effects

- Adds or refreshes `//!` module docs and `///` declaration docs.
- Never modifies runtime behaviour.
- No commits.

## Goals

1. Make modules understandable at a glance.
2. Show real usage quickly.
3. Document behavior and caveats precisely.
4. Keep comments concise, accurate, and executable in spirit.

## Comment levels

### 1) Module-level docs (`//!`)

At the top of each module:

- Explain what the module is for.
- Call out major design/semantic choices (immutability, ordering, complexity,
  equality/hash behavior, numeric semantics, etc.).
- Add a `## Quick Start` block with realistic examples.
- Use embedded links for referenced modules, for example:
  [`kestrel:data/array`](/docs/kestrel:data/array).
- Do not refer readers to test files.

Template:

```kestrel
//! One-line module purpose.
//!
//! Key semantics, guarantees, caveats.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as M from "kestrel:data/<module>"
//!
//! // realistic example flow
//! ```
```

### 2) Function docs (`///`)

For each exported function:

- Start with an action verb: "Return", "Create", "Convert", "Apply", "Split".
- Include critical behavior details:
  - edge cases (empty input, out-of-range indexes, zero divisors)
  - return shape (`Option`, `Result`, etc.)
  - mutation vs copy semantics
  - ordering guarantees (or lack thereof)
- Add complexity when useful (`O(n)`, `O(1)`), especially for collections.

Good style:

```kestrel
/// Return the first `n` elements. Safe when `n > length(xs)`.
```

## Example quality guidelines

Examples should be:

- Minimal but realistic (not toy placeholders).
- Focused on common workflows.
- Written in idiomatic Kestrel (pipe where it improves readability).
- Consistent with actual exported API names and argument order.

Prefer examples that demonstrate:

- creation + transform + query in one short flow
- error handling (`match Ok/Err`, `Option` fallback)
- conversion between related types (`List <-> Array`, parse/stringify, etc.)

## Accuracy checklist

Before finishing:

- Verify every documented function/signature exists.
- Verify examples use valid function names and argument order.
- Ensure caveats match implementation (copy vs mutate, ordering guarantees,
  truncation/floor semantics, etc.).
- Keep language neutral and precise; avoid hand-wavy claims.

## Kestrel stdlib conventions

- Use `//!` for module docs and `///` for declaration docs.
- Prefer interpolation over append-style string building in examples.
- Keep comments ASCII.
- Do not add docs to test files unless explicitly requested.
- When mentioning another module in prose, use an embedded link to `/docs/...`
  instead of plain code formatting.
- Do not include "see test file" referrals in module docs.

## Example

For a model stdlib module with the documentation level this skill targets, see [stdlib/kestrel/data/list.ks](../../../stdlib/kestrel/data/list.ks). It has a rich `//!` module block with Performance and Sorting subsections, a runnable Quick Start example, and concise per-function `///` docs covering behaviour, complexity, and edge cases.

## Suggested patch strategy

1. Read module header and exported declarations.
2. Add/refresh top `//!` docs and Quick Start block.
3. Tighten `///` docs for exported declarations.
4. Preserve code behavior; documentation-only edits should not change runtime.
5. Run targeted checks if needed (`./kestrel test` or relevant subset).
