# fix(codegen): ListExpr spread-element check incorrectly matches RecordExpr

## Sequence: S08-11
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Discovered while implementing: S08-05 (Phase C — ast.test.ks)

## Summary

The JVM codegen `ListExpr` handler used `'spread' in el` to detect spread-list elements
(of the form `{ spread: true, expr: Expr }`).  This check incorrectly triggered for any
`RecordExpr` node because TypeScript's optional-property representation means that a
TypeScript object always contains every declared optional property key — even if its
value is `undefined`.  So `'spread' in el` returned `true` for any record literal that
appeared inside a list literal, causing the codegen to follow the spread code path with an
`undefined` expression, and subsequently crash with:

```
Cannot read properties of undefined (reading 'kind')
```

The crash manifested whenever a record literal appeared directly inside a list literal in
a function-call scrutinee of a `match` expression (the pattern first hit in `ast.test.ks`
at Phase C of S08-05).

## Current State

**FIXED.** The fix was applied in commit `63ccd25` during S08-05 Phase C:

```diff
- if ('spread' in el) {
+ if (el.spread === true) {
```

The fix ensures only genuine spread wrappers (where `spread` is explicitly `true`) take
the spread code path.  All 420+ compiler tests were verified to pass after the fix.

## Relationship to other stories

- Fixed as part of: S08-05 (Phase C, ast.ks / ast.test.ks)
- Related codegen bugs found in the same session: S08-08, S08-09, S08-10

## Goals

*(Already achieved.)*

1. ~~Change `'spread' in el` to `el.spread === true` in `codegen.ts` ListExpr handler~~
2. ~~Verify no regression in compiler tests~~

## Acceptance Criteria

- [x] The following program compiles and runs without crashing:
  ```kestrel
  val items = [{ x = 1, y = 2 }, { x = 3, y = 4 }]
  ```
- [x] No regression in 420+ compiler tests.

## Spec References

None — this is a compiler defect, not a language spec change.

## Build Notes

*Fixed 2026-04-06 in commit `63ccd25`.*

Root cause: TypeScript optional property `spread?: boolean` means the key string `"spread"`
is always present in a `RecordExpr` JavaScript object (as `undefined`), so `'spread' in el`
evaluated to `true` for all record nodes.  The fix `el.spread === true` distinguishes
genuine spread wrappers from plain records.

No code in `parser.ks` needed adjustment; the only change was one character in
`compiler/src/jvm-codegen/codegen.ts`.
