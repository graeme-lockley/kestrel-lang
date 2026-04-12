# VSCode Extension: Same-File Go-to-Definition and Keyword/Local Completion

## Sequence: S10-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-06, S10-07, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Implement `textDocument/definition` for same-file bindings and `textDocument/completion` for language keywords, local bindings, and imported names. Cmd-clicking a function call, variable use, or ADT constructor navigates to its declaration in the same file. The completion list offers all language keywords and every name currently in scope at the cursor: `fun`/`val`/`var` names, `type` names, ADT constructors, `exception` names, and imported names from the file's `import {}` statements.

## Current State

No go-to-definition or completion provider exists. The compiler's `Program.body` provides top-level declarations and `Program.imports` provides imported bind names. The typecheck environment maps names to their types but does not expose a scope-at-cursor API.

## Relationship to other stories

- **Depends on S10-02** (document-manager) and **S10-04** (the `collectDeclarations` helper from the symbols provider).
- Cross-file go-to-definition (for imported names navigating to their original module) is deferred to S10-12 (requires E04 + E07).
- S10-07 (signature help) builds on the completion infrastructure (same scope-collection logic).

## Goals

1. Add `vscode-kestrel/src/server/providers/definition.ts`: given a cursor offset, finds the `IdentExpr` or `IdentType` node at that position, resolves its name against the declaration table built from `program.decls`, and returns an LSP `Location` for the declaration's span.
2. Add `vscode-kestrel/src/server/providers/completion.ts`: collects completions from (a) a hard-coded keyword list, (b) names from `program.decls` (top-level declarations), (c) names from `program.imports` (named imports), and (d) parameter names visible at the cursor position from enclosing `FunDecl` / `LambdaExpr` nodes. Returns `CompletionItem[]` with appropriate `kind` values (Function, Variable, Keyword, Class).
3. Register both providers in `server.ts` and declare `definitionProvider: true` and `completionProvider: { triggerCharacters: ['.'] }` in server capabilities.
4. Unit tests for `definition.ts`: resolved and unresolved name cases.
5. Unit tests for `completion.ts`: keyword completions present; local name completions present; imported names present.

## Acceptance Criteria

- Cmd-clicking a top-level function name (call site) navigates to its `fun` declaration in the same file.
- Cmd-clicking a `val`/`var` name navigates to its declaration.
- Completion popup opens with all language keywords when triggered.
- Local `fun` and `val` names appear in the completion list.
- Names from `import { X, Y } from "..."` appear in the completion list.
- Completion items for functions have a `Function` kind icon; types have `Class`; keywords have `Keyword`.

## Spec References

- `docs/specs/01-language.md` §import declarations — import syntax and bind names.

## Risks / Notes

- Go-to-definition for ADT constructors (e.g., `Some(x)`) requires recognizing `PascalCase` call expressions as constructor references and mapping them to the `ConstructorDef` span inside the `TypeDecl`.
- Parameter-level completion (names from enclosing `FunDecl.params`) requires a scope walk up the AST from the cursor position. The `findNodeAtOffset` helper from S10-03 should be extended or accompanied by a `collectScopeAt(program, offset): Map<string, InternalType>` helper.
- Completion snippets (e.g., `fun name(params) = ...`) are left for a future enhancement; this story delivers plain name completions only.

## Impact analysis

| Area | Change |
|------|--------|
| Definition provider | Add `vscode-kestrel/src/server/providers/definition.ts` resolving same-file identifiers to declaration spans. |
| Completion provider | Add `vscode-kestrel/src/server/providers/completion.ts` merging keyword, import, and declaration completions. |
| LSP server wiring | Register `definitionProvider` and `completionProvider` capabilities and handlers in `server.ts`. |
| Tests | Add unit tests for definition resolution and completion list coverage. |

## Tasks

- [ ] Add `vscode-kestrel/src/server/providers/definition.ts` that resolves same-file `IdentExpr`/`IdentType` names to declaration locations in `Program.body`.
- [ ] Add `vscode-kestrel/src/server/providers/completion.ts` that returns keyword, import-name, top-level declaration, and constructor completions.
- [ ] Register `onDefinition` and `onCompletion` handlers in `vscode-kestrel/src/server/server.ts` and advertise capabilities.
- [ ] Add `vscode-kestrel/test/unit/definition.test.ts` for resolved and unresolved name lookup.
- [ ] Add `vscode-kestrel/test/unit/completion.test.ts` for keyword/import/declaration completion coverage.
- [ ] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/definition.test.ts` | Verify same-file symbol lookup returns declaration location and unresolved names return null. |
| Vitest unit | `vscode-kestrel/test/unit/completion.test.ts` | Verify completion items include language keywords, imports, functions, vals/vars, and constructor names. |
| Manual extension smoke | VS Code extension host | Cmd-click navigates to same-file declaration and completion menu includes expected names. |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — verify import/declaration forms consumed by completion and definition providers are aligned; no textual change expected in this story.
- [ ] `docs/specs/09-tools.md` — no change in this story; consolidated editor capability docs remain in S10-09.
