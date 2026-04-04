# Epic E10: VSCode Extension — Language Server and Editor Integration

## Status

Unplanned

## Summary

Delivers a feature-rich Visual Studio Code extension for Kestrel (`.ks` files), built on the Language Server Protocol (LSP). The extension bundles a dedicated Kestrel Language Server that imports the compiler directly (Node.js), providing sub-second diagnostics, hover-type popups, code completion, go-to-definition, find-references, rename, and code actions — all powered by the inferred-type annotations and source-span metadata already present in the compiler's typed AST. Later stories layer in document formatting (via `kestrel fmt` from E08), doc-comment hover (via the `///` syntax and `/api/index` endpoint from E09), cross-file navigation (depending on E04 and E07), and refactoring actions such as exhaustiveness quick-fix, extract-function, and organize-imports. The extension is distributed as a `.vsix` package and published to the VS Code Marketplace.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- **E07 (Incremental Compilation)** — `.ksi` metadata files allow the language server to re-type-check only the open file on every keystroke, making cross-file diagnostics and navigation sub-second. Cross-file features (go-to-definition across modules, find-references, rename, workspace symbols) depend on E07 for acceptable performance; single-file features can land before E07 is complete.
- **E08 (Source Formatter)** — provides `kestrel fmt` (used by the document-formatting provider and format-on-save), the `kestrel:dev/parser` module (token ranges for semantic tokens), and the stdlib namespace restructure that the LSP resolver must understand.
- **E09 (Documentation Browser)** — introduces `///` / `//!` doc-comment syntax and the `/api/index` JSON endpoint; the hover provider reads from this index to render doc-comment Markdown in type popups. E10 can ship without E09 (hover shows type only); doc-comment hover is an additive enhancement.
- **E04 (Module Resolution and Reproducibility)** — stable, canonical package identities are required for reliable go-to-definition and find-references across packages.

E10 stories are tiered so that Tier 1 (syntax highlighting, diagnostics, hover, same-file navigation) can be implemented and released before E07/E08/E09 are complete. Tier 2+ stories carry explicit per-story dependencies on those epics.

## Epic Completion Criteria

- The extension activates automatically for all `*.ks` files and is installable from a `.vsix` or the VS Code Marketplace.
- Syntax highlighting correctly colors keywords (`fun`, `val`, `type`, `match`, `if`, `extern`, `async`, …), type names, ADT constructors, operators (`|>`, `::`), string/numeric literals, and `//` / `/* */` comments via a TextMate grammar.
- Parse errors, type errors, and module-resolution errors appear as red squiggles; hovering the squiggle shows the human-readable message with `hint` and `suggestion` fields (spec 10).
- Hovering over any expression shows its inferred Hindley–Milner type in a Markdown popup (e.g. `(String) -> Int`, `Task<Result<String, Error>>`).
- The document outline (OUTLINE panel, breadcrumbs) lists all top-level declarations (`fun`, `val`, `var`, `type`, ADT constructors, `exception`).
- Go-to-definition works for same-file bindings (functions, `val`/`var`, type aliases, ADT constructors, `exception` names).
- Completion offers all language keywords, local bindings, imported names, and stdlib exports at the cursor.
- Signature help displays parameter names and types while typing a function call.
- Inlay hints show the inferred type next to `val x = ...` and untyped `fun` parameters.
- Semantic token coloring distinguishes type names, constructor names, function names, and variable names beyond what the TextMate grammar can achieve.
- `kestrel fmt` formats the active file on save when `editor.formatOnSave` is enabled (requires E08 to be complete).
- A code action for `type:non_exhaustive_match` generates the missing `match` arms from the ADT constructor list.
- A code action for `type:unknown_variable` suggests `import { X } from "..."` additions when the name is found in a resolvable module.
- Go-to-definition navigates across files (requires E04 + E07).
- Find-references and rename work across the workspace (requires E04 + E07).
- Hover shows `///` doc-comment prose beneath the type (requires E09).
- A CodeLens above each `test(...)` call lets the developer run that individual test via `kestrel test`.
- `docs/specs/09-tools.md` is extended with an "Editor Integration" section documenting the LSP server entry point, the supported protocol version, and configurable settings (path to `kestrel` binary, debounce interval).
- All unit and integration tests in `vscode-kestrel/` pass.

## Implementation Approach

### Repository layout

The extension lives in a `vscode-kestrel/` top-level directory (or a separate repository linked as a subtree). It is a TypeScript project with two compilation targets: the **extension host** (`src/extension.ts`) and the **language server** (`src/server/server.ts`), following the standard `vscode-languageclient` / `vscode-languageserver` split.

```
vscode-kestrel/
  package.json                   ← VS Code extension manifest + LSP dependencies
  tsconfig.json
  src/
    extension.ts                 ← starts LSP client, registers commands/tasks
    server/
      server.ts                  ← Language Server entry point
      document-manager.ts        ← in-memory source + annotated-AST cache per file
      compiler-bridge.ts         ← imports compiler/dist/ directly (no subprocess)
      providers/
        diagnostics.ts           ← textDocument/publishDiagnostics
        hover.ts                 ← textDocument/hover (inferred type + doc-comment)
        completion.ts            ← textDocument/completion
        definition.ts            ← textDocument/definition
        references.ts            ← textDocument/references
        rename.ts                ← textDocument/rename
        symbols.ts               ← textDocument/documentSymbol + workspace/symbol
        folding.ts               ← textDocument/foldingRange
        semanticTokens.ts        ← textDocument/semanticTokens/full
        inlayHints.ts            ← textDocument/inlayHint
        codeActions.ts           ← textDocument/codeAction
        formatting.ts            ← textDocument/formatting (calls kestrel fmt)
        signatureHelp.ts         ← textDocument/signatureHelp
        codeLens.ts              ← textDocument/codeLens (test runner)
  syntaxes/
    kestrel.tmLanguage.json      ← TextMate grammar
  language-configuration.json   ← bracket pairs, indentation, comment tokens
  test/
    unit/                        ← provider unit tests (Vitest)
    e2e/                         ← end-to-end tests (VS Code extension test runner)
```

### Language Server lifecycle

1. Extension activates on the first `*.ks` file open.
2. Extension spawns `node vscode-kestrel/dist/server.js` over stdio.
3. LSP client negotiates capabilities; server declares support for all implemented methods.
4. On `didOpen` / `didChange`: `document-manager` caches source text and enqueues a compile (250 ms debounce).
5. `compiler-bridge` calls `compile(source, { sourceFile })` → typed AST + diagnostics in one synchronous call (no subprocess).
6. Diagnostics published; typed AST stored keyed by URI.
7. Feature requests (hover, completion, …) resolved against the cached typed AST with no recompile.

### Key compiler hooks used

| LSP feature | Compiler API |
|-------------|-------------|
| Diagnostics | `compile()` → `Diagnostic[]` with `location.line/column/offset` |
| Hover type | `getInferredType(node)` on span-matched AST node + new `printType()` utility |
| Go-to-definition | AST walk for declaration with matching name; `span.start/end` → VS Code `Location` |
| Document symbols | Top-level `FunDecl`, `TypeDecl`, `ValDecl`, `VarDecl`, `ExceptionDecl` with `span` |
| Semantic tokens | `tokenize()` → `Token[]` with kind + span for precise coloring |
| Exhaustiveness fix | `exportedConstructors: Map<string, InternalType>` from `typecheck()` result |
| Formatting | `kestrel fmt --stdin` subprocess (E08) |
| Cross-file | `compileFileJvm()` with E07 `.ksi` metadata for incremental type-check |

### Hover type display

A new `printType(t: InternalType): string` utility is added to `compiler/src/types/print.ts`. It renders `InternalType` to a human-readable Kestrel type string:

| Internal type | Displayed as |
|--------------|-------------|
| `tInt` | `Int` |
| `String → String` | `(String) -> String` |
| `{ name: String }` | `{ name: String }` |
| `Option<List<Int>>` | `Option<List<Int>>` |
| `Task<Result<String, Error>>` | `Task<Result<String, Error>>` |

### Feature tiers and epic dependencies

| Tier | Features | Required epic |
|------|----------|--------------|
| 1 | Syntax highlighting, diagnostics, hover type, document symbols, folding, same-file go-to-definition, completion (keywords/locals), semantic tokens, inlay hints, signature help | None beyond compiler |
| 2 | Cross-file go-to-definition, find-references, rename, workspace symbols, cross-module completion | E04 + E07 |
| 3 | Format on save, range formatting | E08 |
| 3 | Hover doc-comments | E09 |
| 4 | Code actions (exhaustiveness fix, add import, extract function, organize imports) | Tier 1 |
| 5 | Test CodeLens, task runner integration, Marketplace publish | Tier 1 |
