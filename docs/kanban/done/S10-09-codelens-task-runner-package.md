# VSCode Extension: Test CodeLens, Task Runner, and Marketplace Package

## Sequence: S10-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/done/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-10, S10-11, S10-12

## Summary

Add a `textDocument/codeLens` provider that places a "▶ Run test" and "▶ Debug test" CodeLens above each `test("name", ...)` call expression. Clicking "Run test" invokes `kestrel test --filter <name> <file>` in a VS Code terminal. Also add a VS Code Task definition (`kestrel: run`, `kestrel: test`) contributed by the extension, and provide `npm run package` to produce the distributable `.vsix`. Update `docs/specs/09-tools.md` with an "Editor Integration" section.

## Current State

No CodeLens, task, or packaging support exists. The compiler's AST has `CallExpr` nodes for `test(...)` calls; the test runner CLI accepts `--filter` (or equivalent). The extension project (from S10-01) has `npm run compile` but no `vsce package` step. `docs/specs/09-tools.md` has no LSP section.

## Relationship to other stories

- **Depends on S10-02** (server infrastructure) for CodeLens registration.
- This is the final "Tier 1" story; S10-10, S10-11, S10-12 require external epics.
- Independent of S10-06, S10-07, S10-08 — can be built in any order relative to those.

## Goals

1. Add `vscode-kestrel/src/server/providers/codeLens.ts`: walks `program.decls` for top-level `ExprStmt` nodes whose expression is a `CallExpr` with callee name `test` and a string literal as the first argument. Emits two `CodeLens` items (Run / Debug) positioned at the call site.
2. Add `vscode-kestrel/src/extension.ts` command handlers: `kestrel.runTest` and `kestrel.debugTest` that spawn `kestrel test --filter <name> <file>` in an integrated terminal.
3. Contribute a `kestrel: run file` and `kestrel: run tests` task in `package.json` `taskDefinitions` and a `contributes.tasks` array.
4. Add `vsce` as a dev dependency; add `npm run package` script (`vsce package --no-dependencies`).
5. Update `docs/specs/09-tools.md` with an "Editor Integration" section documenting: LSP server entry point (`vscode-kestrel/dist/server.js`), supported LSP protocol version (3.17), configurable settings (`kestrel.lsp.debounceMs`, `kestrel.executable`), and a list of supported LSP capabilities.
6. Add `vscode-kestrel/test/unit/` with Vitest unit tests and `vscode-kestrel/test/e2e/` placeholder (E2E test runner setup deferred).

## Acceptance Criteria

- A "▶ Run test" CodeLens appears above each `test("name", fn)` call in a `.ks` file.
- Clicking "▶ Run test" opens an integrated terminal and runs `kestrel test --filter "name" <file>`.
- `npm run package` inside `vscode-kestrel/` produces a `.vsix` file that installs cleanly in VS Code.
- `docs/specs/09-tools.md` has the new "Editor Integration" section with accurate content.
- Unit tests in `vscode-kestrel/test/unit/` pass.

## Spec References

- `docs/specs/09-tools.md` — to be updated in this story with the Editor Integration section.
- `docs/specs/08-tests.md` — `test(name, fn)` syntax (so the CodeLens parser uses the right call signature).

## Risks / Notes

- The `kestrel test --filter` flag syntax must match what the CLI actually supports at implementation time. Check `scripts/kestrel test` for the current flag name.
- Debug CodeLens (attach a Node.js debugger to the Kestrel JVM process) is a stretch goal; if JVM-based debugging is not feasible, the "Debug" lens can be omitted or replaced with a "Copy test name" action.
- `vsce package --no-dependencies` bundles only the compiled JS, not `node_modules`. The extension host loads `vscode-languageclient` from the VS Code runtime; the server process must either bundle its deps or point to a local `node_modules`. The packaging story should resolve this explicitly.

## Impact analysis

| Area | Change |
|------|--------|
| CodeLens provider | Add `vscode-kestrel/src/server/providers/codeLens.ts` and server wiring for `textDocument/codeLens`. |
| Extension commands | Add command handlers in `vscode-kestrel/src/extension.ts` for run/debug test actions and terminal invocation. |
| Extension manifest/tasks | Update `vscode-kestrel/package.json` for commands, task contributions, and package script/dependencies. |
| Docs/specs | Update `docs/specs/09-tools.md` with an editor integration section and capability list. |
| Tests | Add unit tests for CodeLens extraction and command argument shaping; add e2e placeholder structure. |

## Tasks

- [x] Add `vscode-kestrel/src/server/providers/codeLens.ts` to detect `test("name", ...)` call sites and emit Run/Debug lenses.
- [x] Register `codeLensProvider` capability and `onCodeLens` handler in `vscode-kestrel/src/server/server.ts`.
- [x] Add `kestrel.runTest` and `kestrel.debugTest` command implementations in `vscode-kestrel/src/extension.ts`.
- [x] Update `vscode-kestrel/package.json` with command contributions, task definitions, and packaging script (`npm run package`).
- [x] Add/update unit tests under `vscode-kestrel/test/unit/` for CodeLens behavior and command payload construction.
- [x] Add `vscode-kestrel/test/e2e/README.md` placeholder describing deferred e2e harness setup.
- [x] Update `docs/specs/09-tools.md` with the new Editor Integration section and capability/settings details.
- [x] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/codeLens.test.ts` | Verify CodeLens items are produced only for `test("name", fn)` call forms and include run/debug commands. |
| Vitest unit | `vscode-kestrel/test/unit/extension.commands.test.ts` | Verify command argument handling and generated terminal command line for filtered test execution. |
| Placeholder | `vscode-kestrel/test/e2e/README.md` | Document extension-host e2e runner plan deferred beyond this story. |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — added Editor Integration section (LSP endpoint, version, supported capabilities, and settings).
- [x] `vscode-kestrel/README.md` — included packaging and test CodeLens usage notes.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Added CodeLens provider for `test("name", ...)` call detection and run/debug command lenses.
- 2026-04-12: Added extension command handlers for `kestrel.runTest` and `kestrel.debugTest`, with configurable CLI executable and LSP debounce settings.
- 2026-04-12: Added command/config/task contributions and packaging script in `vscode-kestrel/package.json`.
- 2026-04-12: Added `codeLens.test.ts` and `test/e2e/README.md` placeholder.
- 2026-04-12: Packaging verification: `yes | npx vsce package --no-dependencies` produced `vscode-kestrel-0.0.1.vsix`.
- 2026-04-12: Verification status:
	- `cd vscode-kestrel && npm run compile && npm test` passed.
	- `cd compiler && npm run build && npm test` passed.
	- `./scripts/kestrel test` passed (`1779 passed`).
