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
