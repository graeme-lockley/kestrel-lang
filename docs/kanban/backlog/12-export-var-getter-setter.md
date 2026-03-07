# Export Var Getter/Setter Compilation

## Priority: 12 (High)

## Summary

Spec 07 &sect;5.1 defines that an `export var` produces two function table entries: a **getter** (0-arity, reads the global) and a **setter** (1-arity, writes the global). Importing modules use these to read and assign to the exported variable. Assignment to an imported var (`x := expr`) compiles to CALL with the setter index. This is not fully implemented.

## Current State

- The compiler supports `export val` (getter only via LOAD_GLOBAL/STORE_GLOBAL pattern).
- `export var` may compile but the setter function is not emitted in the function table.
- The `.kti` file does not include `setter_index` for var exports.
- The importing module cannot compile `x := expr` for an imported var because no setter target exists.
- `docs/specs/export-var-setter-sketch.md` exists with design notes.

## Acceptance Criteria

- [ ] `export var x = expr` emits two entries in the function table:
  - Getter: 0-arity function that does `LOAD_GLOBAL idx; RET`.
  - Setter: 1-arity function that does `LOAD_LOCAL 0; STORE_GLOBAL idx; LOAD_CONST unit; RET`.
- [ ] `.kti` includes both `function_index` (getter) and `setter_index` for var exports.
- [ ] Importing module: `x := expr` compiles to evaluating `expr`, then `CALL setter_index 1`.
- [ ] Importing module: reading `x` compiles to `CALL getter_index 0`.
- [ ] E2E test: module A exports a var, module B imports it, reads it, assigns to it, reads the new value.

## Spec References

- 07-modules &sect;5.1 (export var getter/setter in types file)
- 07-modules &sect;9 (Assignment to imported var calls setter)
- 03-bytecode-format &sect;6.6 (Imported function table may have getter + setter entries)
