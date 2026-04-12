# VSCode Extension: Hover Type Display and printType Utility

## Sequence: S10-03
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Add `textDocument/hover` support to the language server. Hovering over any expression, binding, or type annotation in a `.ks` file shows the inferred Hindley–Milner type in a Markdown popup (e.g., `(String) -> Int`, `Option<List<Int>>`). This requires a new `printType(t: InternalType): string` utility in `compiler/src/types/print.ts` and a span-walk helper that finds the deepest AST node whose span covers the cursor position.

## Current State

- `getInferredType(node)` exists in `compiler/src/typecheck/check.ts` and is exported from `compiler/src/typecheck/index.ts`.
- `InternalType` variants are fully defined in `compiler/src/types/internal.ts`.
- A local `typeToString()` function exists in `compiler/src/compile-file-jvm.ts` but is private and handles only the AST-level `Type` (not `InternalType`).
- No public `printType` for `InternalType` exists.
- No span-walk utility exists in the compiler; the LSP server will need to traverse the AST to find the node covering a given offset.

## Relationship to other stories

- **Depends on S10-02** for the LSP server and document-manager infrastructure.
- S10-06 (semantic tokens) and S10-07 (signature help) also need the span-walk helper introduced here; those stories can reuse it.
- S10-11 (hover doc-comments, requires E09) extends the hover response to include doc-comment prose below the type.

## Goals

1. Add `compiler/src/types/print.ts` exporting `printType(t: InternalType): string` that renders all `InternalType` variants to canonical Kestrel type syntax (table in epic's Implementation Approach).
2. Export `printType` from `compiler/src/types/index.ts`.
3. Add `compiler/src/ast/walk.ts` exporting `findNodeAtOffset(program: Program, offset: number): NodeBase | null` — returns the deepest node whose `span.start <= offset < span.end`.
4. Add `vscode-kestrel/src/server/providers/hover.ts` — given a URI and LSP `Position`, converts position to offset, calls `findNodeAtOffset`, calls `getInferredType`, calls `printType`, and returns a `MarkupContent` hover response.
5. Register the hover provider in `server.ts` and declare `hoverProvider: true` in server capabilities.
6. Unit tests for `printType` covering: primitives, arrow types, generic app types, tuples, records, nested generics, and type schemes (displayed with hidden quantifier, just the body).

## Acceptance Criteria

- Hovering over a bound name (function, `val`, `var`) shows its inferred type in the hover popup.
- Hovering over a sub-expression (e.g., a literal, a binary expression) shows the inferred type of that expression.
- Hovering over whitespace or positions with no span match returns no hover.
- `printType` unit tests all pass (`cd compiler && npm test`).
- The hover response is formatted as a Markdown code block so VS Code renders it in a monospace font.

## Spec References

- `docs/specs/06-typesystem.md` — type syntax that `printType` must reproduce.

## Risks / Notes

- `findNodeAtOffset` must handle the case where `span` is absent on a node (many synthetic nodes lack spans). It should skip span-less nodes and continue the walk.
- Type variable ids in `{ kind: 'var'; id: number }` should be displayed as `'a`, `'b`, etc. (first free variable encountered → `'a`, second → `'b`) rather than the raw integer.
- `{ kind: 'scheme' }` nodes should display their instantiated body (hide the `∀` quantifier) since the user is usually looking at a specific use-site.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler type utilities | Add `compiler/src/types/print.ts` and export `printType` from `compiler/src/types/index.ts`. |
| Compiler AST helpers | Add `compiler/src/ast/walk.ts` with span-based `findNodeAtOffset` traversal. |
| LSP compiler bridge | Extend `vscode-kestrel/src/server/compiler-bridge.ts` to retain typed AST and query inferred type at cursor offset. |
| LSP document state | Extend `DocumentManager` state to store AST data alongside source and diagnostics. |
| LSP hover provider | Add `vscode-kestrel/src/server/providers/hover.ts` and register `textDocument/hover` capability in `server.ts`. |
| Tests | Add compiler unit tests for `printType` and extension unit tests for hover response mapping. |

## Tasks

- [x] Add `compiler/src/types/print.ts` implementing `printType(t: InternalType): string` for all `InternalType` variants.
- [x] Export `printType` from `compiler/src/types/index.ts`.
- [x] Add `compiler/src/ast/walk.ts` implementing `findNodeAtOffset(program, offset)` and export it from `compiler/src/ast/index.ts`.
- [x] Add compiler unit tests for `printType` under `compiler/test/unit/`.
- [x] Extend `vscode-kestrel/src/server/document-manager.ts` and `compiler-bridge.ts` to cache AST and return hover type text for a cursor offset.
- [x] Add `vscode-kestrel/src/server/providers/hover.ts` and wire hover capability + handler in `vscode-kestrel/src/server/server.ts`.
- [x] Add `vscode-kestrel/test/unit/hover.test.ts` covering hover hit/miss behavior.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/types-print.test.ts` | Verify canonical display of primitive, arrow, app, tuple, record, union/intersection, and scheme types. |
| Vitest unit | `vscode-kestrel/test/unit/hover.test.ts` | Verify hover returns markdown code block type text for a valid node and `null` when no node/type exists. |
| Manual extension smoke | VS Code extension host | Hover over `.ks` identifiers/expressions and confirm inferred type popup appears. |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` — verified printed type syntax used in hover matches spec notation; no textual spec change required in this story.
- [x] `docs/specs/09-tools.md` — no change in this story; hover capability listing is documented in S10-09.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Added compiler `printType` and AST span walker (`findNodeAtOffset`) to support cursor-based type lookup.
- 2026-04-12: Extended extension compiler bridge/document state to cache parsed+typed AST and serve hover type strings.
- 2026-04-12: Added hover provider with Markdown code-block response and unit tests (`hover.test.ts`).
- 2026-04-12: Verification results: `cd compiler && npm run build && npm test` PASS, `cd vscode-kestrel && npm run compile && npm test` PASS, `./scripts/kestrel test` PASS (1754 passed).
