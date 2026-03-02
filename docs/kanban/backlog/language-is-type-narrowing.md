# Language: `is` type narrowing

## Description

Per spec 01 §2.4 (keyword `is`) and 06 §4, the expression `x is T` checks structural conformance (e.g. record shape, ADT constructor). In `if (x is T) { ... }`, the type of `x` in the then-branch is narrowed to `original_type & T`. The grammar and type system specify this, but the compiler does not yet implement it: no `is` keyword in the lexer/parser, and no narrowing in typecheck or codegen.

## Acceptance Criteria

- [ ] Lexer: add `is` as reserved keyword (01 §2.4)
- [ ] Parser: add expression form `e is T` (primary or relational level as specified in 01)
- [ ] Typecheck: in conditional `if (e is T) { body }`, type of `e` in body is narrowed to intersection of inferred type of `e` and `T`; ensure `T` is a type that can narrow (record shape, ADT constructor, or structural subtype per 06 §4)
- [ ] Codegen: emit a runtime conformance check for `e is T` when used in conditionals (or document that typecheck guarantees conformance and no runtime check is needed for well-typed programs)
- [ ] Add conformance tests: valid program using `if (x is SomeRecord) { ... x.field ... }`; invalid program where `T` cannot narrow (if applicable)
