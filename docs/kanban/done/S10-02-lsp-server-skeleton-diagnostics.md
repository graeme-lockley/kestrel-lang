# VSCode Extension: LSP Server Skeleton and Live Diagnostics

## Sequence: S10-02
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Wire up a Language Server Protocol server (`src/server/server.ts`) rooted in `vscode-languageserver/node` and an LSP client in `src/extension.ts` rooted in `vscode-languageclient/node`. The server imports `compiler/dist/index.js` directly (no subprocess), maintains an in-memory document cache, and publishes `textDocument/publishDiagnostics` after a 250 ms debounce on every `didOpen`/`didChange` event. The result is red squiggles for parse errors and type errors in `.ks` files, backed by the compiler's `Diagnostic[]` with `location.line/column` and `hint`/`suggestion` fields (spec 10).

## Current State

`vscode-kestrel/` was bootstrapped in S10-01 with a stub `src/extension.ts` that only logs on activation. No LSP client or server code exists. The compiler's public `compile()` function already returns `{ ok: false; diagnostics: Diagnostic[] }` with full source location data.

## Relationship to other stories

- **Depends on S10-01** for the project scaffold and build pipeline.
- S10-03 through S10-09 all extend the same server module created here; the document-manager and compiler-bridge are the shared foundation.
- Cross-file diagnostics (module-resolution errors for multi-file projects) improve with E07 incremental compilation, but single-file diagnostics are fully testable without it.

## Goals

1. Add `vscode-languageclient` and `vscode-languageserver` npm dependencies to `vscode-kestrel/package.json`.
2. Create `src/server/document-manager.ts`: maintains a `Map<uri, { source: string; ast: Program | null; diagnostics: Diagnostic[] }>`, exposes `update(uri, source)` and `get(uri)`.
3. Create `src/server/compiler-bridge.ts`: exposes `compileSource(source: string): { ast: Program | null; diagnostics: Diagnostic[] }` by calling the compiler's `compile()` and `typecheck()`.
4. Create `src/server/server.ts`: initializes an LSP connection over stdio, handles `initialize`, `textDocument/didOpen`, `textDocument/didChange`, `textDocument/didClose`; debounces recompile (250 ms) and calls `connection.sendDiagnostics()`.
5. Update `src/extension.ts` to start the server as a child process and connect a `LanguageClient`.
6. Map compiler `Diagnostic` → LSP `Diagnostic` including `severity`, `message`, `range` (converted from 0-based offset to 1-based line/character), `hint`, and `suggestion` as `relatedInformation`.
7. Integration test: open a file with a type error → diagnostic appears; fix the file → diagnostic clears.

## Acceptance Criteria

- Opening a `.ks` file with a syntax error shows a red squiggle at the correct position.
- Opening a `.ks` file with a type error shows a red squiggle; hovering shows hint/suggestion text when present.
- Saving a corrected file clears all diagnostics.
- The language server does not crash on empty files, files with only comments, or files with `import` declarations.
- `npm run compile` inside `vscode-kestrel/` still succeeds.

## Spec References

- `docs/specs/10-compile-diagnostics.md` — severity levels, hint, suggestion, related locations.
- `docs/specs/09-tools.md` — "Editor Integration" section to be added (spec update deferred to one of the later stories).

## Risks / Notes

- The compiler's `compile()` function in `compiler/src/index.ts` currently returns the typed AST only on success. The LSP server needs the typed AST even when there are errors for partial feature support. The compiler-bridge may need to call `parse()` + `typecheck()` separately so partial ASTs are available.
- The debounce interval (250 ms default) should be configurable via a VS Code setting (`kestrel.lsp.debounceMs`) to allow users on slow machines to increase it.
- The compiler runs synchronously; for large files this may block the server event loop. If this proves to be a problem, wrap in a `setImmediate` tick or worker thread (deferred concern).

## Impact analysis

| Area | Change |
|------|--------|
| Extension host | Replace scaffold `src/extension.ts` with language-client startup/teardown that launches the server over IPC transport. |
| LSP server | Add `src/server/server.ts` with initialize, open/change/close handlers and publishDiagnostics pipeline. |
| Compiler bridge | Add `src/server/compiler-bridge.ts` to call `compile()` from the built compiler and normalize diagnostics output. |
| Document state | Add `src/server/document-manager.ts` to cache in-memory source text and latest diagnostics per URI. |
| Package/build config | Add `vscode-languageclient` and `vscode-languageserver` deps and a `compile:server` build target. |
| Tests | Add unit tests for diagnostic mapping and debounce-triggered diagnostic publication behavior. |

## Tasks

- [x] Add dependencies and scripts in `vscode-kestrel/package.json` for `vscode-languageclient` and `vscode-languageserver` and dual compile targets.
- [x] Implement `vscode-kestrel/src/server/document-manager.ts` with update/get/delete operations for document source and diagnostics.
- [x] Implement `vscode-kestrel/src/server/compiler-bridge.ts` that calls compiler `compile(source, { sourceFile })` and returns diagnostics in a server-friendly shape.
- [x] Implement `vscode-kestrel/src/server/server.ts` with LSP connection lifecycle, 250ms debounced compile on open/change, and diagnostic clearing on close.
- [x] Update `vscode-kestrel/src/extension.ts` to start a `LanguageClient` wired to the server module.
- [x] Implement diagnostic conversion helper (compiler `Diagnostic` -> LSP `Diagnostic`) including severity mapping and hint/suggestion enrichment.
- [x] Add tests under `vscode-kestrel/test/unit/` for diagnostic conversion and debounce behavior.
- [x] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/diagnostics.test.ts` | Verify severity/range/message mapping from compiler diagnostics to LSP diagnostics, including hint/suggestion text. |
| Vitest unit | `vscode-kestrel/test/unit/server.debounce.test.ts` | Verify rapid successive changes emit one compile/publish cycle after debounce. |
| Manual extension smoke | VS Code extension host | Open `.ks` file with parse/type errors and confirm red squiggles appear and clear after fix. |

## Documentation and specs to update

- [x] `docs/specs/10-compile-diagnostics.md` — reviewed mapped fields (`hint`, `suggestion`, `related`) against LSP diagnostic mapping; no spec text change required in this story.
- [x] `docs/specs/09-tools.md` — no spec text change in this story; full Editor Integration section remains in S10-09.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Added LanguageClient startup in extension host and new server modules (`server.ts`, `document-manager.ts`, `compiler-bridge.ts`, `diagnostics.ts`, `debounce.ts`).
- 2026-04-12: Added diagnostic mapping and debounce unit tests (`diagnostics.test.ts`, `server.debounce.test.ts`).
- 2026-04-12: Verification results: `cd vscode-kestrel && npm run compile && npm test` PASS; `cd compiler && npm run build && npm test` PASS.
- 2026-04-12: Repository-wide `./scripts/kestrel test` currently fails on unrelated in-progress compiler work at `stdlib/kestrel/tools/compiler/classfile.ks` (`Unknown variable: count`), outside S10-02 scope.
