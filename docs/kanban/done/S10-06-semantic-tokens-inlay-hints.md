# VSCode Extension: Semantic Token Coloring and Inlay Hints

## Sequence: S10-06
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-07, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Implement `textDocument/semanticTokens/full` and `textDocument/inlayHint`. Semantic tokens allow VS Code themes to distinguish type names, ADT constructors, function names, and variable names with precise coloring beyond what the TextMate grammar (S10-01) can achieve. Inlay hints display the inferred type next to untyped `val x = ...` bindings and untyped function parameters.

## Current State

- The lexer's `tokenize()` exports `Token[]` with `kind` and `span` fields, covering keyword tokens precisely.
- The compiler's typecheck step annotates every AST node with its `InternalType` via `setInferredType`.
- `printType` was added in S10-03.
- No semantic token or inlay hint providers exist.

## Relationship to other stories

- **Depends on S10-02** (document-manager, cached AST/tokens) and **S10-03** (`printType`, `findNodeAtOffset`).
- Independent of S10-04, S10-05, S10-07 — can be built in any relative order.
- The `tokenize()` call for semantic tokens is a separate pass from the compile result; the server already runs the compiler which internally tokenizes.

## Goals

1. Add `vscode-kestrel/src/server/providers/semanticTokens.ts`: calls `tokenize(source)` on the cached source, maps each `Token` to a semantic token `(line, startChar, length, tokenType, tokenModifiers)`, distinguishing token types: `keyword`, `type` (PascalCase ident in type position), `enum` (PascalCase ident in expression/constructor position), `function` (ident that resolves to a `FunDecl`), `variable`, `string`, `number`, `operator`, `comment`. Emits the encoded delta arrays per the LSP `SemanticTokens` spec.
2. Declare the `legend` (token type + modifier lists) in server capabilities and register `semanticTokensProvider`.
3. Add `vscode-kestrel/src/server/providers/inlayHints.ts`: walk `program.decls` for `ValDecl` nodes without an explicit type annotation and `FunDecl` parameter nodes without type annotations; for each, call `getInferredType` + `printType` and emit an `InlayHint` with `kind: Type` positioned just after the name token.
4. Register `inlayHintsProvider: true` in server capabilities and handle `textDocument/inlayHint`.
5. Unit tests for `inlayHints`: a `val x = 42` produces an inlay hint `: Int`; an annotated `val x: Int = 42` does not.

## Acceptance Criteria

- Type names (e.g., `Option`, `List`, `String`) are colored as types by the active VS Code theme's semantic token colors.
- ADT constructor tokens (e.g., `Some`, `None`, `True`, `False`) are colored as enum members.
- Function declaration names are colored as functions.
- Inlay hints show `: <type>` after `val x = ...` bindings that have no explicit annotation.
- Inlay hints are hidden when `editor.inlayHints.enabled` is off (VS Code handles this automatically once the provider is registered).
- `npm run compile` succeeds after adding the providers.

## Spec References

- `docs/specs/06-typesystem.md` — type naming conventions that inform the token type classifications.

## Risks / Notes

- Determining whether a PascalCase identifier is a type vs. constructor vs. module requires resolving it against the declaration environment. A heuristic (PascalCase in type position → type, PascalCase in expression/call position → constructor) is acceptable for this story; full resolution improves with S10-12.
- The semantic token delta encoding is stateful and order-dependent. Use the `vscode-languageserver` library's `SemanticTokensBuilder` if available, rather than implementing the delta calculation manually.
- Inlay hints for complex inferred types (deeply nested generics) can be verbose. Limit display to types that `printType` renders to ≤60 characters; longer types show as `...` with the full type in the hover.

## Impact analysis

| Area | Change |
|------|--------|
| Semantic token provider | Add `vscode-kestrel/src/server/providers/semanticTokens.ts` to tokenize source and emit semantic tokens with a declared legend. |
| Inlay hint provider | Add `vscode-kestrel/src/server/providers/inlayHints.ts` to emit type hints for unannotated `val`/`var` and function params. |
| Compiler bridge | Expose tokenizer and inferred-type text helpers used by semantic and inlay providers. |
| LSP server wiring | Register semantic tokens and inlay hints capabilities/handlers in `server.ts`. |
| Tests | Add unit tests for inlay hint behavior and semantic token collection sanity. |

## Tasks

- [x] Extend `vscode-kestrel/src/server/compiler-bridge.ts` with helpers for tokenization and inferred-type text rendering.
- [x] Add `vscode-kestrel/src/server/providers/semanticTokens.ts` with token legend and token collection using compiler lexer tokens.
- [x] Add `vscode-kestrel/src/server/providers/inlayHints.ts` for untyped binding/param type hints.
- [x] Register `semanticTokensProvider` and `inlayHintProvider` capabilities and handlers in `vscode-kestrel/src/server/server.ts`.
- [x] Add `vscode-kestrel/test/unit/inlayHints.test.ts` covering untyped and explicitly typed declaration behavior.
- [x] Add `vscode-kestrel/test/unit/semanticTokens.test.ts` covering baseline token extraction/classification behavior.
- [x] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/inlayHints.test.ts` | Verify untyped declarations emit type hints and explicitly typed declarations do not. |
| Vitest unit | `vscode-kestrel/test/unit/semanticTokens.test.ts` | Verify semantic token collector emits tokens for keywords/types/functions/variables on representative source lines. |
| Manual extension smoke | VS Code extension host | Confirm semantic coloring and inlay hints appear in `.ks` files with inferred types. |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` — verified inlay type displays use canonical type syntax; no textual spec change required in this story.
- [x] `docs/specs/09-tools.md` — no change in this story; editor capability docs remain in S10-09.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Added semantic token provider, inlay hint provider, and server capability wiring.
- 2026-04-12: Extended compiler bridge with tokenization and inferred-type helper APIs used by these providers.
- 2026-04-12: Added semantic token and inlay hint unit tests; `cd vscode-kestrel && npm run compile && npm test` PASS.
- 2026-04-12: Verification results: `cd compiler && npm run build && npm test` PASS; `./scripts/kestrel test` PASS (1764 passed).

## Build notes

- 2026-04-12: Started implementation.
