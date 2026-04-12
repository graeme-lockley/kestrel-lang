# VSCode Extension: Signature Help

## Sequence: S10-07
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Implement `textDocument/signatureHelp`. While the user is typing a function call, a signature popup appears showing the function name, parameter names, and their types, with the current argument highlighted. This reuses the inferred type of the callee expression (arrow type) and the span information of the call's argument list.

## Current State

No signature help provider exists. The compiler's typecheck result makes `getInferredType` available on any `CallExpr` node. A `CallExpr` node in the AST contains `callee` (expression) and `args` (array of expressions) with spans. The arrow type of the callee carries the parameter type list.

## Relationship to other stories

- **Depends on S10-02** (document-manager) and **S10-03** (`findNodeAtOffset`, `printType`).
- Builds naturally on S10-05 (completion) since both share the pattern of resolving the callee at the cursor.
- Independent of S10-06, S10-08, S10-09 — can be built in any relative order.

## Goals

1. Add `vscode-kestrel/src/server/providers/signatureHelp.ts`: given a cursor offset, walks the AST to find the enclosing `CallExpr`; extracts the callee's inferred type (if an arrow type); builds a `SignatureInformation` with `label` (e.g., `add(a: Int, b: Int): Int`), `parameters` array with ranges into the label string, and `activeParameter` index computed from the number of commas before the cursor within the argument list.
2. Register `signatureHelpProvider: { triggerCharacters: ['(', ','] }` in server capabilities.
3. Edge cases: callee type is not an arrow (e.g., calling a variable of unknown type) → return `null`. Callee is a multi-param curried function → show all params. Varargs are not in the current language; no special handling needed.
4. Unit tests: a call to a 2-argument function with cursor on the second argument shows `activeParameter: 1`.

## Acceptance Criteria

- Typing `add(` immediately shows the signature popup with parameter names and types.
- Moving the cursor past the `,` advances the highlighted parameter.
- Closing the `)` dismisses the popup.
- Calling a value whose type is not a function does not show a popup.

## Spec References

- `docs/specs/01-language.md` §function declarations — parameter syntax.

## Risks / Notes

- Kestrel supports curried function application only through explicit multi-param `fun`. There is no partial application syntax in the current language, so the active-parameter calculation is straightforward.
- Named arguments are not a current language feature; all arguments are positional.
- If the callee expression has an unresolved type variable (e.g., the callee itself is a type error), `printType` will show `'a` for the unknown parameter; this is acceptable.
