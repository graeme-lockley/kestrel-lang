# Documentation Browser: Infer Exported val/var Types

## Sequence: S09-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser (kestrel doc)](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-05, S09-07

## Summary

Extend the documentation index pipeline so exported val and var declarations include inferred types in their doc signatures, even when no explicit type annotation is present in source. The docs browser should show the same inferred type shape developers see in compiler diagnostics and hover tooling.

## Current State

The current doc pipeline can format declaration signatures, but exported val/var declarations without explicit type annotations may display incomplete or generic signatures. This creates an information gap versus compiler output and makes docs less useful for API consumers.

## Relationship to other stories

- Depends on S09-03 (declaration signature pretty-printer) and S09-07 (doc server integration).
- Enables better usability for S09-10 (syntax-colorized declarations) by ensuring complete type text exists to highlight.
- Independent of S09-12 (index layout polish).

## Goals

1. Ensure exported val/var declarations always carry a resolved type string in the extracted doc model.
2. Use type inference when source declarations omit explicit annotation.
3. Keep formatting consistent with existing signature rendering output for functions and annotated bindings.
4. Expose inferred type details through both HTML views and JSON index output.

## Acceptance Criteria

- Exported val declarations without explicit type annotations show inferred types in module and declaration docs pages.
- Exported var declarations without explicit type annotations show inferred types in module and declaration docs pages.
- `/api/index` includes inferred type strings for affected declarations.
- If inference fails for an exported binding, the docs output is stable and includes a clear fallback marker instead of crashing.

## Spec References

- docs/specs/06-typesystem.md
- docs/specs/09-tools.md

## Risks / Notes

- Type inference work in docs must not duplicate compiler logic in a divergent way; prefer reusing canonical type rendering/typecheck output paths.
- Inference for mutually recursive exports may require explicit ordering or additional metadata from existing compiler phases.
- Any new fallback marker for unresolved types should be documented in planned-story docs updates.
