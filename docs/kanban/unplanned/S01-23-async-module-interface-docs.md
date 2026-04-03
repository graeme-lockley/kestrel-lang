# Document Async Semantics in the Module System Spec

## Sequence: S01-23
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

The module system spec (`docs/specs/07-modules.md`) and the type system spec (`docs/specs/06-typesystem.md`) do not document how `async fun` interacts with module exports, imports, and the type system's structural approach to async. Specifically: async-ness is structural (any function returning `Task<T>` satisfies `(A) -> Task<T>`), higher-order functions accepting `(A) -> Task<T>` work equally for `async fun` and regular functions returning `Task<T>`, and there is no way to require a function to be "truly async" (launched on a virtual thread) at the type level. These facts should be explicitly documented to prevent confusion and to serve as a reference when S01-12 and S01-13 are planned.

## Current State

- `docs/specs/07-modules.md` — no mention of `async fun` export/import rules.
- `docs/specs/06-typesystem.md` — `Task<T>` is documented as a type but the structural equivalence of `async fun f(): Task<T>` and `fun f(): Task<T>` at call sites is not.
- `docs/specs/01-language.md` §5 documents the semantics of `async fun` and `await` at the expression level, but not in the context of module boundaries or higher-order functions.

## Relationship to other stories

- Documentation only; no code changes.
- S01-12 (block-local async fun) and S01-13 (Task combinators) will produce spec updates that should be consistent with the principles documented here.
- Write this first to establish the canonical reference, or after S01-12/S01-13 to consolidate.

## Goals

1. `docs/specs/07-modules.md` gains a section on async exports: rule that `async fun` exported from a module is typed as its `(params) -> Task<T>` signature at import sites; callers cannot distinguish async from non-async by type alone.
2. `docs/specs/06-typesystem.md` documents the structural nature of `Task<T>`: any `(A) -> Task<T>` is interchangeable with `async (a: A) => body` from the type perspective.
3. The prohibition on top-level `await` (outside an async function) is noted in both specs.
4. Cross-module async calling (importing and calling an `async fun` from another module) is described, including the codegen requirement to use the `KTask`-returning descriptor.

## Acceptance Criteria

- `docs/specs/07-modules.md` contains a subsection on async exports/imports.
- `docs/specs/06-typesystem.md` contains a note on structural async typing.
- No code changes; docs-only story.
- Content is reviewed against the actual implementation for accuracy before closing.

## Spec References

- `docs/specs/07-modules.md` (primary target).
- `docs/specs/06-typesystem.md` (secondary target).
- `docs/specs/01-language.md` §5 (existing async semantics — cross-reference, no change needed).

## Risks / Notes

- This is a pure documentation story; risk is low.
- Ensure the structural equivalence note accurately reflects the implementation: `async fun` actually dispatches on a virtual thread, while a regular `fun` returning `Task<T>` must manually call a runtime submit. This distinction is an implementation detail not visible at the type level — document it accurately.
