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
