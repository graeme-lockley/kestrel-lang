# ignore keyword for discarding non-void values

## Description

Introduce `ignore expr` to explicitly discard the result of an expression that returns a non-Unit value. Expressions returning Unit (e.g. `print(x)`) can remain bare statements. Using `ignore` on a Unit-returning expression should be an error.

From earlier design discussion: `ignore expr` is valid only when expr has non-Unit type; error when expr returns Unit.

## Acceptance Criteria

- [ ] Add `ignore` keyword to lexer; parse `ignore Expr` as statement
- [ ] Typecheck: `ignore expr` requires expr has non-Unit type; error if Unit
- [ ] Typecheck: require binding or `ignore` for non-Unit expression statements (or allow implicit discard per spec)
- [ ] Codegen: emit expr, discard result (no store)
- [ ] Conformance tests: valid `ignore compute()` when compute returns non-Unit; invalid `ignore print(x)` (Unit)
- [ ] Update spec 01 if grammar changes
