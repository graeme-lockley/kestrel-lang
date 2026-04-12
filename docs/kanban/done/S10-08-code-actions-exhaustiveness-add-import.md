# VSCode Extension: Code Actions — Exhaustiveness Fix and Add Import

## Sequence: S10-08
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-09, S10-10, S10-11, S10-12

## Summary

Implement `textDocument/codeAction` with two quick-fix actions: (1) **Exhaustiveness fix** — when a `match` expression raises `type:non_exhaustive_match`, generate the missing `match` arms from the ADT constructor list; (2) **Add import** — when `type:unknown_variable` names a top-level binding found in a resolvable stdlib or project module, insert an `import { X } from "..."` line at the top of the file.

## Current State

No code action provider exists. The compiler publishes diagnostics with error codes (e.g., `type:non_exhaustive_match`, `type:unknown_variable`) and the `location.offset` of the affected token. The typecheck result includes the set of expected constructors for exhaustiveness errors via the diagnostic `hint` field. Stdlib module paths are resolvable.

## Relationship to other stories

- **Depends on S10-02** (diagnostics and document-manager) and **S10-05** (completion infrastructure for resolving module names).
- Independent of S10-06, S10-07 — can be built in any relative order after S10-02 + S10-05.
- The "add import" action's module-resolution step becomes more powerful with E04 + E07 (cross-package), but stdlib resolution works without them.

## Goals

1. Add `vscode-kestrel/src/server/providers/codeActions.ts` with:
   - `exhaustivenessFixAction(diagnostic, program, source)`: parses the constructor names from `diagnostic.hint`, synthesizes `| ConstructorName(_) => todo!()` arm text, and returns a `WorkspaceEdit` text-insertion at the end of the existing `match` arm list.
   - `addImportAction(diagnostic, program, source)`: reads `diagnostic.message` to extract the unknown name, searches the stdlib module index (a hard-coded map of export name → module specifier for Tier 1; dynamic lookup from E07 `.ksi` files for Tier 2), and returns a `WorkspaceEdit` inserting `import { Name } from "module:path"` after the last existing import line.
2. Register `codeActionProvider: { codeActionKinds: ['quickfix'] }` in server capabilities.
3. The `textDocument/codeAction` handler filters on `context.diagnostics` codes so actions only appear on the relevant squiggle.
4. Unit tests: given an `unknown_variable` diagnostic for `println`, the action proposes `import { println } from "kestrel:io/console"`.

## Acceptance Criteria

- Hovering a `type:non_exhaustive_match` squiggle and activating Code Actions shows "Add missing match arms"; applying it inserts the correct arms.
- Hovering a `type:unknown_variable` squiggle and activating Code Actions shows "Import X from '...'"; applying it adds the import line.
- No code action is offered if the diagnostic code is not one of the two handled codes.
- Applied edits maintain correct indentation for the target file.

## Spec References

- `docs/specs/10-compile-diagnostics.md` — error codes `type:non_exhaustive_match` and `type:unknown_variable`.
- `docs/specs/01-language.md` §match — match arm syntax.

## Risks / Notes

- The exhaustiveness-fix insertion point (where to add missing arms) must be derived from the last existing `match` arm's `span.end`. If spans are missing on `Case` nodes, a fallback of appending before the closing `}` of the `MatchExpr` is acceptable.
- The stdlib module name → export-name index must be kept in sync with `stdlib/kestrel/`. A static map covering the most-used exports (`println`, `List`, `Option`, common math functions) is acceptable for Tier 1; a full dynamic index requires E07.
- The `todo!()` placeholder in generated arms should be a call to a stdlib `todo` function if one exists, or the string literal `"TODO"` otherwise — whichever is defined in the stdlib at implementation time.

## Impact analysis

| Area | Change |
|------|--------|
| Code action provider | Add `vscode-kestrel/src/server/providers/codeActions.ts` to synthesize quick-fix edits from diagnostics. |
| LSP server wiring | Register `codeActionProvider` capability and `onCodeAction` handler in `vscode-kestrel/src/server/server.ts`. |
| Import resolution | Add a Tier 1 static export-to-module lookup map for high-value stdlib symbols used by add-import quick fix. |
| Tests | Add `vscode-kestrel/test/unit/codeActions.test.ts` for exhaustiveness/add-import positive and negative cases. |

## Tasks

- [x] Add `vscode-kestrel/src/server/providers/codeActions.ts` with `collectCodeActions` and helper builders for `type:non_exhaustive_match` and `type:unknown_variable`.
- [x] Implement non-exhaustive match quick-fix text generation from diagnostic hints (missing constructor names) and produce insertion edit near the target `match` block.
- [x] Implement unknown-variable add-import quick-fix with a Tier 1 static stdlib export index and insertion after existing imports.
- [x] Register `codeActionProvider` and `onCodeAction` in `vscode-kestrel/src/server/server.ts`.
- [x] Add `vscode-kestrel/test/unit/codeActions.test.ts` covering: exhaustiveness fix action, add-import action, and no-action for unrelated diagnostics.
- [x] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/codeActions.test.ts` | Verify `type:non_exhaustive_match` yields a quick-fix containing synthesized missing arms. |
| Vitest unit | `vscode-kestrel/test/unit/codeActions.test.ts` | Verify `type:unknown_variable` for `println` yields import fix targeting `kestrel:io/console`. |
| Vitest unit | `vscode-kestrel/test/unit/codeActions.test.ts` | Verify unrelated diagnostics produce no quick-fix actions. |

## Documentation and specs to update

- [x] `docs/specs/10-compile-diagnostics.md` — validated code-action assumptions against current diagnostic code/hint/message shapes; no textual change required.
- [x] `docs/specs/09-tools.md` — no change in this story; editor integration doc updates are grouped in S10-09.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Added `codeActions` provider with two quick fixes: missing match arms (`type:non_exhaustive_match`) and add-import (`type:unknown_variable`).
- 2026-04-12: Wired `codeActionProvider` capability and `onCodeAction` handler in the language server.
- 2026-04-12: Added `codeActions.test.ts` to cover add-import, missing-arm insertion, and no-op diagnostic filtering.
- 2026-04-12: Verification status:
   - `cd vscode-kestrel && npm run compile && npm test` passed.
   - `cd compiler && npm run build && npm test` passed.
   - `./scripts/kestrel test` currently fails in unrelated self-hosting story code (`kestrel:tools/compiler/kti` assertion mismatch in `stdlib/kestrel/tools/compiler/kti.test.ks`).
- 2026-04-12: Re-ran `./scripts/kestrel test`; full harness passed (`1779 passed`).
