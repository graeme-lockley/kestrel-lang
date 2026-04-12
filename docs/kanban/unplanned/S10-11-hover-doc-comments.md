# VSCode Extension: Hover Doc-Comments (requires E09)

## Sequence: S10-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-12

## Summary

Augment the hover provider (S10-03) to display `///` doc-comment prose beneath the inferred type in the hover popup. When E09 introduces `///` / `//!` doc-comment syntax and the `/api/index` JSON endpoint, the hover provider reads the doc-comment for the hovered binding and appends it as Markdown below the type line.

## Current State

The hover provider from S10-03 shows only the inferred type. E09 (Documentation Browser epic) introduces `///` doc-comment parsing into the compiler and a doc-index JSON API. Until E09 is complete, doc-comments are not parsed and are not available in the typed AST.

## Relationship to other stories

- **Blocked by E09** — `///` doc-comment parsing must land in the compiler before this story can be implemented.
- **Depends on S10-03** — extends the existing hover provider rather than replacing it.
- Independent of S10-10, S10-12.

## Goals

1. Extend `compiler-bridge.ts` to also expose `getDocComment(name: string): string | null` by querying the E09 doc-index or reading `///` comment text directly from the typed AST node's attached comment field.
2. Update `vscode-kestrel/src/server/providers/hover.ts` to append the doc-comment Markdown below a horizontal rule after the type, when a doc-comment is available.
3. Hover format when doc-comment present:
   ```
   ```kestrel
   (String) -> Int
   ```
   ---
   Converts a decimal string to an integer. Returns `0` if the string is not a valid integer.
   ```
4. Unit test: a function with a `/// doc` comment produces a hover response containing both the type string and the doc text.

## Acceptance Criteria

- Hovering over a `fun` with a `///` doc-comment shows the doc prose in the hover popup below the type.
- Hovering over a binding without a doc-comment shows only the type (unchanged from S10-03).
- The doc-comment text is rendered as Markdown (bold, inline code, links work in the VS Code hover widget).

## Spec References

- E09 stories (once planned) for `///` syntax and doc-index API.

## Risks / Notes

- The exact API that E09 exposes for doc-comment access is not yet defined. This story should be planned (i.e., moved to `planned/`) only after E09's doc-comment AST representation is stable.
- Doc-comment text may contain Markdown; it should be passed through as-is rather than escaped, since VS Code renders hover Markdown natively.
