# Types File (.kti) Full Spec 07 Compliance

## Priority: 55 (High)

## Summary

The types file (`.kti`) is the compile-time artifact that allows cross-module compilation without re-parsing/re-compiling dependencies. The current implementation exists but needs completion to fully satisfy spec 07 &sect;5 -- particularly around `export var` getter/setter indices, complete type serialization, and ensuring all exported declarations are covered.

## Current State

- `types-file.ts` writes and reads JSON `.kti` files with:
  - `version: 1`
  - `functions` map: export name -> `{ kind, function_index, arity, type }` for functions and vals
- `compile-file.ts` uses `.kti` files for incremental builds (freshness check by mtime).
- **Gaps**:
  - `export var` does not emit `setter_index` per spec 07 &sect;5.1.
  - Type serialization is partial -- may not round-trip all type forms (union, intersection, row variables, ADT type params).
  - Exported type aliases (from the ADT/type table) may not be included.
  - No validation that the `.kti` format matches between compiler versions.

## Acceptance Criteria

- [ ] `export var` entries include both `function_index` (getter) and `setter_index` per spec 07 &sect;5.1.
- [ ] Type serialization covers all InternalType forms: prim, arrow, record (with row), app (generics), tuple, union, intersection, scheme (quantified), type variables.
- [ ] Exported type aliases are included in the `.kti` file.
- [ ] Round-trip test: write a `.kti`, read it back, verify all fields are preserved.
- [ ] Integration test: compile module A that exports a var, compile module B that imports and assigns to it, verify getter/setter indices are correct in the bytecode.
- [ ] Imported function table (03 &sect;6.6) entries use the correct indices from the `.kti` file.

## Spec References

- 07-modules &sect;5 (Compilation artifacts: types file format)
- 07-modules &sect;5.1 (export var getter/setter)
- 03-bytecode-format &sect;6.6 (Imported function table)
