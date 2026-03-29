# Types File (.kti) Full Spec 07 Compliance


## Sequence: 30
## Former ID: 55
## Priority: 55 (High)

## Summary

The types file (`.kti`) is the compile-time artifact that allows cross-module compilation without re-parsing/re-compiling dependencies. The current implementation exists but needs completion to fully satisfy spec 07 &sect;5 -- particularly around `export var` getter/setter indices, complete type serialization, and ensuring all exported declarations are covered.

## Current State

- `types-file.ts` writes and reads JSON `.kti` files with:
  - `version: 1`
  - `functions` map: export name -> `{ kind, function_index, arity, type }` for functions and vals; `setter_index` for vars
- `compile-file.ts` uses `.kti` files for incremental builds (freshness check by mtime).
- **Gaps** (addressed):
  - `export var` emits `setter_index` per spec 07 &sect;5.1.
  - Type serialization covers all InternalType forms; round-trip tests added.
  - Exported type aliases are included in the `.kti` file.
  - Version validation on read.

## Acceptance Criteria

- [x] `export var` entries include both `function_index` (getter) and `setter_index` per spec 07 &sect;5.1.
- [x] Type serialization covers all InternalType forms: prim, arrow, record (with row), app (generics), tuple, union, intersection, scheme (quantified), type variables.
- [x] Exported type aliases are included in the `.kti` file.
- [x] Round-trip test: write a `.kti`, read it back, verify all fields are preserved.
- [x] **Integration test**: compile module A that exports a var, compile module B that imports and assigns to it, verify getter/setter indices are correct in the bytecode.
- [x] Imported function table (03 &sect;6.6) entries use the correct indices from the `.kti` file.
- [x] **Documentation**: Update all relevent specification documents allowing the decisions and formats and rationale to be well communicated and understood.

## Tasks

- [x] Add round-trip test in types-file.test.ts (all export kinds + type forms)
- [x] Create fixture modules export_var_pkg.ks and import_assign_var.ks
- [x] Add integration test: export var + import and assign, verify bytecode imported function table
- [x] Add kti-format.md; update 07-modules.md and export-var-setter-sketch.md

## Spec References

- 07-modules &sect;5 (Compilation artifacts: types file format)
- 07-modules &sect;5.1 (export var getter/setter)
- 03-bytecode-format &sect;6.6 (Imported function table)
