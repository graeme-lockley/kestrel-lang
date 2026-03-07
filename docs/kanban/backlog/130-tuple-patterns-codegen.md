# Tuple Pattern Matching in Codegen

## Priority: 130 (Medium)

## Summary

Tuple patterns `(p1, p2, p3)` are parsed and typed but may not be fully handled in codegen's match compilation. Since tuples are compiled as records with numeric field names, tuple pattern matching needs to destructure by field index.

## Current State

- Parser handles tuple patterns: `(a, b)` parsed as `TuplePattern`.
- Type checker handles tuple types and patterns.
- Codegen compiles tuple expressions as records with fields named `"0"`, `"1"`, etc.
- Codegen `compilePattern` may not have a specific case for `TuplePattern` -- needs verification.
- `tests/unit/tuples.test.ks` tests tuple creation and field access but not tuple pattern matching in `match`.

## Acceptance Criteria

- [ ] Verify codegen handles `TuplePattern` in match cases (destructuring to individual elements).
- [ ] If not handled, implement: for `(a, b) => expr`, emit GET_FIELD on the scrutinee record with field indices 0, 1, etc., binding to pattern variables.
- [ ] Add Kestrel test: `match (pair) { (x, y) => x + y }`.
- [ ] Add Kestrel test: nested tuple pattern `match (t) { ((a, b), c) => ... }`.
- [ ] Add Kestrel test: tuple pattern with wildcard `match (t) { (_, y) => y }`.

## Spec References

- 01-language &sect;3.2 (Tuple patterns: `(p1, p2)`)
- 01-language &sect;3.4 (Tuples: comma disambiguates grouping from tuple)
