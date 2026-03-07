# Language: `is` Type Narrowing

## Priority: 75 (Medium)

## Summary

The `is` keyword is reserved (spec 01 &sect;2.4) and used for type narrowing in conditionals (`if (x is T) { ... }`). Within the then-branch, the type of `x` is narrowed to `original_type & T` (spec 06 &sect;4). This feature is not implemented at any level (lexer, parser, type checker, or codegen).

## Current State

- Lexer: `is` is listed as a keyword in `KEYWORDS`.
- Parser: No parsing rule for `is` expressions.
- Type checker: No narrowing logic.
- Codegen: No code generation for runtime `is` checks.

## Acceptance Criteria

- [ ] **Parser**: Parse `expr is Type` as a binary-like expression (or a special expression form). The result type is `Bool`.
- [ ] **Type checker**: In `if (x is T) { thenBranch } else { elseBranch }`, narrow `x` to `original_type & T` in `thenBranch`. In `elseBranch`, `x` retains its original type (or is narrowed to `original_type - T` if subtraction is implementable).
- [ ] **Codegen**: Emit runtime check instructions. For ADT narrowing, check the constructor tag. For record narrowing, check that the record has the required fields (shape compatibility).
- [ ] **VM**: May need a new opcode (e.g., `IS_TYPE` or `CHECK_TAG`) or the check can be compiled as a sequence of existing instructions (GET_FIELD checks, MATCH on tag).
- [ ] Conformance test: `if (x is Some) { ... }` narrows Option to Some.
- [ ] Conformance test: `if (r is { x: Int }) { ... }` narrows a record type.
- [ ] Typecheck invalid test: narrowing to an incompatible type produces a type error.

## Spec References

- 01-language &sect;2.4 (Keywords: `is`)
- 06-typesystem &sect;4 (Unions and intersections; narrowing with `is`)
