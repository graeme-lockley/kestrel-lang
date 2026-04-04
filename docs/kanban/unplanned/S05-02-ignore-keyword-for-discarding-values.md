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
