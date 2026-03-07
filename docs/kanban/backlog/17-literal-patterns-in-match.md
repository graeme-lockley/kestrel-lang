# Literal Patterns in Match (Int, String)

## Priority: 17 (Medium)

## Summary

The parser correctly handles integer and string literal patterns in `match` cases (e.g., `match (x) { 0 => "zero"; 1 => "one"; _ => "other" }`), but the type checker silently ignores them and the codegen does not emit comparison instructions. Literal patterns are non-functional at runtime.

## Current State

- **Parser** (`parse.ts` lines 922-925): Parses `int` and `string` tokens as `LiteralPattern` nodes. Working.
- **AST** (`nodes.ts` lines 358-361): `LiteralPattern` with `literal: 'int' | 'string' | 'true' | 'false'` and `value: string`.
- **Type checker** (`check.ts`): `bindPattern()` has no branch for `LiteralPattern`. It silently passes through without:
  - Unifying the scrutinee type with the literal's type (e.g., `Int` for integer patterns).
  - Reporting an error if the literal type doesn't match the scrutinee type.
- **Codegen** (`codegen.ts`): The match compilation has no case for `LiteralPattern`. Only ADT constructor patterns (via MATCH jump table), wildcard, and variable patterns are handled.

## Design Notes

Literal patterns require a different codegen strategy than ADT patterns:
- ADT patterns use MATCH (jump table by constructor tag).
- Literal patterns need sequential comparison: load the scrutinee, load the literal constant, emit EQ, then JUMP_IF_FALSE to the next case.

This means a match expression could have **mixed** pattern types: some ADT constructors and some literals (unlikely) or all literals. The codegen needs to handle at least the all-literals case.

For Bool patterns (`True`, `False`), the existing MATCH instruction already works (story done). For Int and String literals, a comparison chain is needed.

## Acceptance Criteria

- [ ] **Type checker**: In `bindPattern`, when a `LiteralPattern` is encountered, unify the scrutinee type with `Int` (for integer literals) or `String` (for string literals). Report a type error if they don't unify.
- [ ] **Codegen**: For match cases with literal patterns, emit a comparison chain:
  - For each literal case: emit LOAD of the scrutinee, LOAD_CONST of the literal, EQ, JUMP_IF_FALSE to the next case.
  - For a wildcard/variable catch-all: emit the default branch.
- [ ] **Exhaustiveness**: Literal patterns on Int/String are not exhaustive (infinite domain) unless a wildcard is present. The type checker should require a catch-all pattern when matching on Int or String.
- [ ] Kestrel test: `match (n) { 0 => "zero"; 1 => "one"; _ => "other" }`.
- [ ] Kestrel test: `match (s) { "hello" => 1; "world" => 2; _ => 0 }`.
- [ ] Typecheck invalid: literal pattern on wrong type (e.g., `match (True) { 0 => ... }`).
- [ ] Typecheck invalid: literal match without catch-all pattern.

## Spec References

- 01-language &sect;3.2 (Pattern grammar: INTEGER and STRING as NonConsPattern)
- 06-typesystem &sect;5 (Match exhaustiveness)
- 06-typesystem &sect;8 (Pattern typing: literal patterns require scrutinee to unify with literal type)
