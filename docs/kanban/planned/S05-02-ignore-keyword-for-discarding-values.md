# `ignore` keyword — required discard for non-Unit expressions

## Sequence: S05-02
## Tier: Optional language sugar (after core tiers 1–6)
## Former ID: 27

## Epic

- Epic: [E05 Core Language Ergonomics](../epics/unplanned/E05-core-language-ergonomics.md)
- Companion stories: S05-01

## Summary

Introduce `ignore expr` as the **required** form for any expression-as-statement that produces a non-`Unit` value. A bare non-`Unit` expression in statement position is a **compile error**. This enforces explicit discard semantics: you are never silently dropping a value that might matter. Using `ignore` on a `Unit`-typed expression is also an error — `ignore` is for discarding values, not annotating void calls.

## Motivation

- Silently discarding a non-Unit result (e.g. catching a returned `Result` and doing nothing) is a common source of bugs. Making discard explicit prevents entire classes of accidental omissions.
- A single keyword form is cleaner and more readable than compiler warnings that can be suppressed or ignored.
- `ignore` aligns with languages (OCaml, F#) that require explicit discard and report an error otherwise.

## Current State

- No `ignore` keyword in the lexer.
- No AST node or statement form for discard.
- Expression-as-statement in blocks is currently allowed for any type (no type constraint enforced).
- Spec 01 does not document `ignore`; the statement grammar needs updating.

## Design

### Syntax

```
Stmt ::= ...
       | "ignore" Expr   -- discard a non-Unit result
```

`ignore expr` appears wherever a statement is allowed: inside blocks, at the top level of a function body, etc. It is syntactically a statement, not an expression — `ignore` does not yield a value.

### Typing rules

| Case | Result |
|------|--------|
| `ignore e` where `type(e) ≠ Unit` | OK — evaluates and discards |
| `ignore e` where `type(e) = Unit` | **Compile error**: "`ignore` is not needed for a Unit expression; remove it or use a bare statement" |
| Bare `e` in statement position where `type(e) ≠ Unit` | **Compile error**: "expression of type `T` cannot be used as a statement; use `ignore expr` to explicitly discard the result" |
| Bare `e` in statement position where `type(e) = Unit` | OK — standard void call |

The last item in a block is its return value, not a statement, and is therefore **not** subject to the `ignore` requirement regardless of type.

### Semantics

Evaluate `expr` fully for its side effects; discard the result from the evaluation stack. The JVM codegen emits the expression normally and then pops the result with a `pop` or `pop2` instruction (same as any discarded non-void expression).

### Impact on existing code

Any bare non-Unit expression-as-statement in the stdlib or tests must be updated to use `ignore`. In practice this should be rare: the current stdlib wraps JVM calls returning non-void in `void`-returning `KRuntime` helpers specifically to avoid this issue (see `hashMapPut`, `arrayListSet`, etc.). Any edge cases must be fixed before this story is closed.

## Acceptance Criteria

- [ ] Lexer: add `ignore` as a reserved keyword.
- [ ] Parser: parse `ignore Expr` as a statement node (`IgnoreStmt`); extend block/statement grammar in spec `01-language.md`.
- [ ] Type checker: enforce that bare non-Unit expressions in statement position are a **compile error** (not a warning).
- [ ] Type checker: `ignore e` where `type(e) = Unit` is a **compile error**.
- [ ] Type checker: `ignore e` where `type(e) ≠ Unit` is valid.
- [ ] Codegen (JVM): emit `expr` evaluation followed by `pop`/`pop2` for `IgnoreStmt` (no result stored).
- [ ] Scan stdlib and existing tests; fix any bare non-Unit expression-as-statement violations introduced by this rule.
- [ ] Conformance test (valid): `ignore` with a function returning `Int` succeeds.
- [ ] Conformance test (invalid): `ignore` applied to a `Unit` expression fails with the expected diagnostic.
- [ ] Conformance test (invalid): bare non-`Unit` expression in statement position fails with the expected diagnostic.
- [ ] Kestrel unit test: `ignore` with a mutation function (e.g. `Array.push`) — `push` returns `Unit` so this is a bare statement, *not* an `ignore` site; confirm no error.
- [ ] Update `docs/specs/01-language.md` (statement grammar, `ignore` semantics, block rules).
- [ ] Update `docs/specs/10-compile-diagnostics.md` with dedicated diagnostic codes for: bare non-Unit expression in statement position, and `ignore` applied to Unit.

## Spec References

- `docs/specs/01-language.md` (statements, blocks, Unit type)
- `docs/specs/10-compile-diagnostics.md` (diagnostic codes for discard violations)

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/lexer/types.ts` | Add `'ignore'` to `KEYWORDS` set |
| `compiler/src/ast/nodes.ts` | Add `IgnoreStmt` interface (`kind: 'IgnoreStmt'`, `expr: Expr`); add `IgnoreStmt` to `BlockExpr.stmts` union and to `TopLevelStmt` type |
| `compiler/src/parser/parse.ts` — `parseBlock` | Add `else if (this.at('keyword', 'ignore'))` branch: advance, parse expr, push `{ kind: 'IgnoreStmt', expr }` |
| `compiler/src/typecheck/check.ts` — `ExprStmt` in block | After `inferExpr`, call `apply()`; if result is not `Unit` and not an unresolved type variable, throw `TypeCheckError` with `CODES.type.bare_non_unit_expr` |
| `compiler/src/typecheck/check.ts` — `IgnoreStmt` in block | `inferExpr` the expr, `apply()`; if Unit, throw error with `CODES.type.ignore_unit_expr`; else set inferred type to `tUnit` |
| `compiler/src/typecheck/check.ts` — top-level `ExprStmt` | Same non-Unit check as block case |
| `compiler/src/typecheck/check.ts` — top-level `IgnoreStmt` | Same as block IgnoreStmt case |
| `compiler/src/typecheck/check.ts` — `resolveNode` | Add `if (n2.kind === 'IgnoreStmt') { resolveNode(n2.expr); }` |
| `compiler/src/typecheck/check.ts` — `mainExpr` | Add `if (node.kind === 'IgnoreStmt') return node.expr;` |
| `compiler/src/jvm-codegen/codegen.ts` — `getFreeVars` BlockExpr | Add `else if (stmt.kind === 'IgnoreStmt') walk(stmt.expr);` alongside the ExprStmt case |
| `compiler/src/jvm-codegen/codegen.ts` — `collectLambdas` `walkBlock` | Add `else if (stmt.kind === 'IgnoreStmt') walk(stmt.expr);` |
| `compiler/src/jvm-codegen/codegen.ts` — `emitBlock` | Add `else if (stmt.kind === 'IgnoreStmt') { emitExpr(stmt.expr, mb, tcN, stackDepth); mb.emit1(JvmOp.POP); }` |
| `compiler/src/jvm-codegen/codegen.ts` — top-level init | Add `else if (node.kind === 'IgnoreStmt') { emitExpr(node.expr, initMb); initMb.emit1(JvmOp.POP); }` |
| `compiler/src/diagnostics/types.ts` | Add `bare_non_unit_expr: 'type:bare_non_unit_expr'` and `ignore_unit_expr: 'type:ignore_unit_expr'` to the `type:` block |
| Stdlib/tests audit | Scan all `.ks` files for bare non-Unit expression-as-statement violations introduced by this rule; fix any found |

## Tasks

- [ ] `compiler/src/lexer/types.ts`: add `'ignore'` to the `KEYWORDS` set
- [ ] `compiler/src/ast/nodes.ts`: add `IgnoreStmt` interface; add `IgnoreStmt` to the `BlockExpr.stmts` union (after `ContinueStmt`); add `IgnoreStmt` to the `TopLevelStmt` type alias
- [ ] `compiler/src/parser/parse.ts` — `parseBlock`: add `else if (this.at('keyword', 'ignore'))` branch before the default `else` clause that parses a bare expression; consume the `'ignore'` keyword, parse the inner expression as `'expr'`, push `{ kind: 'IgnoreStmt', expr, span }`; add `'ignore'` to the statement-separator guard (where `'break'`/`'continue'` are checked) so no spurious separator error fires
- [ ] `compiler/src/diagnostics/types.ts`: add `bare_non_unit_expr: 'type:bare_non_unit_expr'` and `ignore_unit_expr: 'type:ignore_unit_expr'` to the `type:` object
- [ ] `compiler/src/typecheck/check.ts` — block `ExprStmt` case: after `inferExpr`, call `const resolved = apply(inferExpr(stmt.expr, asyncCtx))`. If `resolved` is not a type variable (`kind !== 'var'`) and is not `{ kind: 'prim', name: 'Unit' }`, throw `TypeCheckError` with message `"Expression of type <T> cannot be used as a statement; use 'ignore expr' to explicitly discard the result"` and code `CODES.type.bare_non_unit_expr`
- [ ] `compiler/src/typecheck/check.ts` — block: add `IgnoreStmt` branch after `ExprStmt` branch: `inferExpr(stmt.expr, asyncCtx)`. If `apply(...)` is `{ kind: 'prim', name: 'Unit' }`, throw `TypeCheckError` with message `"'ignore' is not needed for a Unit expression; remove it or use a bare statement"` and code `CODES.type.ignore_unit_expr`. Otherwise `setInferredType(stmt, tUnit)`
- [ ] `compiler/src/typecheck/check.ts` — top-level `ExprStmt` (line ~1524): same non-Unit check as block case
- [ ] `compiler/src/typecheck/check.ts` — top-level: add `IgnoreStmt` branch after top-level `ExprStmt` with same logic as block IgnoreStmt
- [ ] `compiler/src/typecheck/check.ts` — `resolveNode`: add `if (n2.kind === 'IgnoreStmt') { resolveNode(n2.expr); }`
- [ ] `compiler/src/typecheck/check.ts` — `mainExpr`: add `if (node.kind === 'IgnoreStmt') return node.expr;`
- [ ] `compiler/src/jvm-codegen/codegen.ts` — `getFreeVars` BlockExpr walk (~line 188): add `else if (stmt.kind === 'IgnoreStmt') walk(stmt.expr);`
- [ ] `compiler/src/jvm-codegen/codegen.ts` — `collectLambdas` `walkBlock` (~line 327): add `else if (stmt.kind === 'IgnoreStmt') walk(stmt.expr);`
- [ ] `compiler/src/jvm-codegen/codegen.ts` — `emitBlock` (~line 1857): add `else if (stmt.kind === 'IgnoreStmt') { emitExpr(stmt.expr, mb, tcN, stackDepth); mb.emit1(JvmOp.POP); }` after the `ExprStmt` case
- [ ] `compiler/src/jvm-codegen/codegen.ts` — top-level init ExprStmt (~line 3486): add `else if (node.kind === 'IgnoreStmt') { emitExpr(node.expr, initMb); initMb.emit1(JvmOp.POP); }` after top-level `ExprStmt` case
- [ ] Audit all stdlib `.ks` files and existing `tests/` `.ks` files for bare non-Unit ExprStmt; fix any violations with `ignore` or by converting them to `val _ = ...` / restructuring
- [ ] `cd compiler && npm run build && npm test`
- [ ] `./scripts/kestrel test`
- [ ] `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance typecheck valid | `tests/conformance/typecheck/valid/ignore_non_unit.ks` | `ignore someIntFn()` typechecks without error |
| Conformance typecheck invalid | `tests/conformance/typecheck/invalid/ignore_unit_expr.ks` | `ignore ()` (or a Unit function call) produces `type:ignore_unit_expr` |
| Conformance typecheck invalid | `tests/conformance/typecheck/invalid/bare_non_unit_expr.ks` | A bare `Int`-returning call in statement position produces `type:bare_non_unit_expr` |
| Conformance runtime valid | `tests/conformance/runtime/valid/ignore_side_effect.ks` | `ignore`-discard a function that returns `Int` as a side-effect wrapper; program produces correct output |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — update statement grammar (§ block / statements): add `"ignore" Expr` as a statement form; document semantics (evaluate and discard non-Unit result); document that bare non-Unit expressions in statement position are a compile error; document that `ignore` on Unit is also an error
- [ ] `docs/specs/10-compile-diagnostics.md` — add `type:bare_non_unit_expr` (bare non-Unit expression in statement position) and `type:ignore_unit_expr` (`ignore` applied to a Unit expression) to the diagnostic code table
