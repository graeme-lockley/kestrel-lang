# VSCode Extension: Document Symbols and Folding Ranges

## Sequence: S10-04
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Implement `textDocument/documentSymbol` and `textDocument/foldingRange`. Document symbols populate the VS Code OUTLINE panel and breadcrumbs with all top-level declarations (`fun`, `val`, `var`, `type`, ADT constructors, `exception`). Folding ranges let the editor collapse `fun` bodies, `type` bodies, `if`/`while`/`match` blocks, and `/* */` multi-line comments.

## Current State

No symbol or folding providers exist. The OUTLINE panel shows nothing for `.ks` files. The compiler's AST (`Program.decls`) exposes all top-level declarations with `span` fields, so these providers can be implemented with a single pass over `program.decls`.

## Relationship to other stories

- **Depends on S10-02** for the document-manager and cached AST.
- Independent of S10-03 (hover), S10-05 (go-to-definition), S10-06 (semantic tokens) — can be implemented in any order relative to those stories.
- S10-05 (go-to-definition) reuses the same declaration list; the two share the `collectDeclarations` helper introduced here.

## Goals

1. Add `vscode-kestrel/src/server/providers/symbols.ts`: walks `program.decls` and returns `DocumentSymbol[]` with `name`, `kind` (Function, Variable, Class for type decls, Constructor, Module for namespaces), `range`, and `selectionRange` derived from `span`.
2. Include nested symbols: ADT constructors are children of their `TypeDecl` parent; record field types are not listed (too noisy).
3. Add `vscode-kestrel/src/server/providers/folding.ts`: collect folding ranges for `fun` bodies (from `{` to `}`), `if`/`while`/`match`/`try` blocks, `type` bodies, and `/* */` comments spanning multiple lines.
4. Register both providers in `server.ts` and declare `documentSymbolProvider: true` and `foldingRangeProvider: true` in server capabilities.
5. Unit tests for `symbols.ts`: given a simple parsed program, the returned `DocumentSymbol[]` array has the expected names, kinds, and ranges.

## Acceptance Criteria

- The OUTLINE panel lists all `fun`, `val`, `var`, `type`, and `exception` declarations in the file with correct names and icons.
- ADT constructors appear as children of their type declaration in the outline tree.
- Clicking an item in the OUTLINE panel navigates to the declaration.
- `fun` bodies and multi-line blocks are collapsible with the fold gutter control.
- Multi-line `/* */` comment blocks are collapsible.

## Spec References

- `docs/specs/01-language.md` — declaration syntax (the source of truth for what counts as a top-level declaration).

## Risks / Notes

- `FunDecl` can appear as a method inside a `TypeDecl` body in future language versions. For now, all `FunDecl` nodes in `program.decls` are top-level.
- Folding for nested blocks (deep `if` inside `fun`) relies on the block `span` being set by the parser. If any block node lacks a `span`, the folding provider must skip it gracefully.
