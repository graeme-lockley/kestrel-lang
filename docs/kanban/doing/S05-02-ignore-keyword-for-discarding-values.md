# `ignore` keyword for discarding non-Unit values

## Sequence: S05-02
## Tier: Optional language sugar (after core tiers 1–6)
## Former ID: 27

## Epic

- Epic: [E05 Core Language Ergonomics](../epics/unplanned/E05-core-language-ergonomics.md)
- Companion stories: 61

## Summary

Introduce `ignore expr` as an explicit statement that evaluates `expr` for side effects and discards its result. This makes intent clear when a function returns a non-`()` value that the program deliberately does not use. Using `ignore` on a `()`-typed expression should be a type error.

## Motivation

- Today, bare expression statements may be restricted or ambiguous depending on type rules; `ignore` gives a single, readable form for "run this, discard the value."
- Aligns with ergonomics in languages that distinguish effectful calls from pure values.

## Current State

- No `ignore` keyword in the lexer.
- No AST node or statement form for discard.
- Spec 01 does not yet document `ignore`; the grammar would need an update when implemented.

## Design

- **Syntax**: `ignore Expr` as a statement (same places as `val`/`var`/expression statements in blocks).
- **Typing**: `expr` must **not** unify with `()` (Unit). If it does, report error: e.g. "ignore is not needed for Unit; use a bare statement or remove ignore."
- **Semantics**: Evaluate `expr` in full; drop the result from the stack / do not bind.
- **Interaction with warnings**: If the compiler warns on unused results, `ignore` should silence that warning for `expr`.

## Acceptance Criteria

- [ ] Lexer: add `ignore` as a keyword.
- [ ] Parser: `ignore Expr` as a statement form; extend block/statement grammar in spec 01.
- [ ] Type checker: require non-Unit type for `expr`; error on Unit.
- [ ] Codegen (JVM): emit evaluation of `expr` without storing the result (same as intentional discard).
- [ ] Kestrel unit test: `ignore` with a function returning `Int` succeeds.
- [ ] Kestrel or conformance test: `ignore` with `()` expression fails typecheck.
- [ ] Update `docs/specs/01-language.md` (statement grammar and semantics).

## Spec References

- 01-language (statements, blocks, Unit type)
- 10-compile-diagnostics (optional: dedicated diagnostic code for misuse of `ignore`)

## Impact analysis

| Area | Change |
|------|--------|
| Lexer (`compiler/src/lexer/types.ts`) | Add `'ignore'` to `KEYWORDS` set. |
| AST (`compiler/src/ast/nodes.ts`) | Add `IgnoreStmt` interface; add it to `BlockExpr.stmts` union; add to `TopLevelStmt`. |
| Parser (`compiler/src/parser/parse.ts`) | In `parseBlock`, handle `at('keyword', 'ignore')` → advance and push `IgnoreStmt`. |
| Type checker (`compiler/src/typecheck/check.ts`) | Add `IgnoreStmt` case: infer expr type; unify with any non-Unit; if expr type IS Unit, emit `CODES.type.ignore_unit` diagnostic error. |
| Diagnostics (`compiler/src/diagnostics/types.ts`) | Add `ignore_unit: 'type:ignore_unit'` code. |
| JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | Add `IgnoreStmt` case alongside `ExprStmt` at the block-statement emit site (line ~1760); `emitExpr` then POP (same as ExprStmt). Also update the two walk/resolve passes (~line 167, 296, 405, 1524, 1557) to include `IgnoreStmt`. |
| Tests | New conformance typecheck test (valid: `ignore Int` succeeds) and (invalid: `ignore ()` errors). New conformance runtime test: `ignore` on a non-Unit value compiles and runs correctly. |
| Docs | `docs/specs/01-language.md` §2.4 (keywords list) and §3.3 (statement grammar + semantics). `docs/specs/10-compile-diagnostics.md` §4 (new error code). |

Compatibility: purely additive; no existing code paths change. Rollback risk: low.

## Tasks

- [ ] Add `'ignore'` to `KEYWORDS` in `compiler/src/lexer/types.ts`.
- [ ] Add `IgnoreStmt` interface to `compiler/src/ast/nodes.ts`; add it to `BlockExpr.stmts` union and `TopLevelStmt`.
- [ ] In `compiler/src/parser/parse.ts` `parseBlock`: add `else if (this.at('keyword', 'ignore'))` branch — advance, parse expression with `'expr'` context, push `IgnoreStmt`.
- [ ] In `compiler/src/typecheck/check.ts`: add `IgnoreStmt` to the block-statement loop — infer expr type; if the inferred type unifies with `tUnit`, throw `TypeCheckError` with `CODES.type.ignore_unit`.
- [ ] Add `ignore_unit: 'type:ignore_unit'` to `compiler/src/diagnostics/types.ts`.
- [ ] In `compiler/src/jvm-codegen/codegen.ts`: add `IgnoreStmt` to all walk passes (three occurrences near lines 167, 296, 1524/1557), the resolve pass, and the emit site near line 1760 (same pattern as `ExprStmt`: `emitExpr` → `POP`).
- [ ] Create `tests/conformance/typecheck/valid/ignore_non_unit.ks` — `ignore` on an `Int`-returning expression compiles without error.
- [ ] Create `tests/conformance/typecheck/invalid/ignore_unit.ks` — `ignore ()` causes `EXPECT: ignore_unit` diagnostic.
- [ ] Create `tests/conformance/runtime/valid/ignore_expr.ks` — runtime test: function returning Int, `ignore`d, does not affect output.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.
- [ ] Update `docs/specs/01-language.md` §2.4 (add `ignore` to keywords list) and §3.3 (add `ignore Expr` to statement grammar with semantics note).
- [ ] Update `docs/specs/10-compile-diagnostics.md` §4 — add `type:ignore_unit` entry.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance typecheck valid | `tests/conformance/typecheck/valid/ignore_non_unit.ks` | `ignore` on non-Unit expr compiles clean |
| Conformance typecheck invalid | `tests/conformance/typecheck/invalid/ignore_unit.ks` | `ignore ()` triggers `type:ignore_unit` error |
| Conformance runtime | `tests/conformance/runtime/valid/ignore_expr.ks` | `ignore` discards value at runtime; subsequent `println` unaffected |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` §2.4 — add `ignore` to the keywords list.
- [ ] `docs/specs/01-language.md` §3.3 — add `| "ignore" Expr` to `Stmt` grammar and explain semantics: evaluates `expr` for side effects, discards result; `expr` must not have type `Unit`.
- [ ] `docs/specs/10-compile-diagnostics.md` §4 — add row: `type:ignore_unit` — "Expression passed to `ignore` has type `Unit`; use a bare expression statement instead."

## Build notes

- 2026-04-04: Started implementation.
