# VSCode Extension: Hover Doc-Comments (requires E09)

## Sequence: S10-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/done/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-12

## Summary

Augment the hover provider (S10-03) to display `///` doc-comment prose beneath the inferred type in the hover popup. When E09 introduces `///` / `//!` doc-comment syntax and the `/api/index` JSON endpoint, the hover provider reads the doc-comment for the hovered binding and appends it as Markdown below the type line.

## Current State

The hover provider from S10-03 shows only the inferred type. E09 (Documentation Browser epic) introduces `///` doc-comment parsing into the compiler and a doc-index JSON API. Until E09 is complete, doc-comments are not parsed and are not available in the typed AST.

## Relationship to other stories

- **Blocked by E09** — `///` doc-comment parsing must land in the compiler before this story can be implemented.
- **Depends on S10-03** — extends the existing hover provider rather than replacing it.
- Independent of S10-10, S10-12.

This story is intentionally isolated from the rest of E10 and should remain unplanned until E09 is complete.

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

## Impact analysis

| Area | Change |
|------|--------|
| LSP hover provider | Extend `vscode-kestrel/src/server/providers/hover.ts` to append doc-comment prose below inferred type markdown when present. |
| Compiler bridge | Add helper(s) in `vscode-kestrel/src/server/compiler-bridge.ts` to locate doc-comment text near the declaration represented by the hovered identifier. |
| Unit tests | Extend `vscode-kestrel/test/unit/hover.test.ts` to verify hover content includes type + markdown doc prose and keeps type-only behavior for undocumented bindings. |
| LSP docs/spec | Update editor integration spec text to describe hover rendering of type + doc-comment markdown in one popup. |

## Tasks

- [x] Add doc-comment extraction helper in `vscode-kestrel/src/server/compiler-bridge.ts` for hovered symbols.
- [x] Update `vscode-kestrel/src/server/providers/hover.ts` to append doc-comment markdown under a separator when docs are available.
- [x] Keep fallback behavior unchanged (type-only hover) when no doc-comment is available.
- [x] Add/extend hover unit tests in `vscode-kestrel/test/unit/hover.test.ts` for type+doc and type-only cases.
- [x] Update `docs/specs/09-tools.md` editor integration text to mention hover doc-comment rendering.
- [x] Run `cd vscode-kestrel && npm test`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/hover.test.ts` | Verify hover markdown includes both inferred type code block and doc-comment prose when docs exist. |
| Vitest unit | `vscode-kestrel/test/unit/hover.test.ts` | Verify hover remains type-only when doc-comment text is missing. |
| Regression suite | `cd compiler && npm run build && npm test` | Ensure extension-side hover changes do not regress compiler suites required by kanban gate. |
| Runtime regression | `./scripts/kestrel test` | Ensure broader project test harness remains stable after extension changes. |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — extend editor integration capability description for hover to mention doc-comment prose rendering.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Implemented hover doc-comment composition by combining inferred type markdown with adjacent `///` prose from source declarations.
- 2026-04-12: Verification passed: `cd vscode-kestrel && npm test`, `cd compiler && npm run build && npm test`, and `./scripts/kestrel test`.
