# VM Float as First-Class Value

## Priority: 20 (Critical)

## Summary

Float is specified as a boxed heap value (spec 05 &sect;1, &sect;2) but is completely non-functional in the VM. Loading a Float constant produces `Value.unit()`. No float arithmetic, comparison, or heap allocation exists. This blocks any program that uses floating-point numbers.

## Current State

- **Constant pool loader** (`load.zig`): Reads Float entries (tag 1) but stores `Value.unit()` -- silently discards the f64.
- **No FLOAT_KIND**: `gc.zig` has no FLOAT heap object kind constant. The GC comment mentions "FLOAT" but nothing is implemented.
- **Arithmetic ops** (ADD, SUB, MUL, DIV, MOD, POW): Only handle `int` tagged values. Float operands would cause undefined behaviour.
- **Comparison ops** (EQ, NE, LT, LE, GT, GE): Only handle `int` and `bool`. No float comparison.
- **JSON workaround**: `primitives.zig` stores f64 bits in an int payload via `@bitCast` for JSON parse/stringify. This is a hack, not general float support.
- **Compiler codegen**: Already emits Float constants with tag 1 in the constant pool. No compiler changes needed.

## Acceptance Criteria

- [ ] Add `FLOAT_KIND` constant to `gc.zig` (e.g., value 6).
- [ ] Implement `allocFloat(f64)` in `gc.zig` -- allocates a heap object with kind FLOAT, stores the f64 payload.
- [ ] Update `load.zig` to call `allocFloat()` for constant pool tag 1 instead of returning `Value.unit()`.
- [ ] Arithmetic instructions (ADD, SUB, MUL, DIV, MOD, POW) check operand tags: if both are `ptr` to FLOAT, perform float arithmetic and return a boxed float result. If one is int and one is float, promote the int to float (or report a type error -- decide based on spec 06 &sect;8 which says both operands must have the same numeric type).
- [ ] Comparison instructions (EQ, NE, LT, LE, GT, GE) support float operands.
- [ ] GC mark phase traces FLOAT objects (no child pointers, just needs to mark the header).
- [ ] `formatInto` in `primitives.zig` formats FLOAT heap objects as decimal (e.g., `1.5`, `3.14159`).
- [ ] Remove or update the JSON f64 `@bitCast` hack to use proper FLOAT heap objects.
- [ ] E2E test: Kestrel program with float literals, arithmetic, comparison, and print.
- [ ] Kestrel unit test: `tests/unit/float.test.ks` covering float operations.

## Spec References

- 01-language &sect;2.7 (Float literals)
- 03-bytecode-format &sect;5 (Constant pool Float tag 1)
- 05-runtime-model &sect;1 (Float is always boxed), &sect;2 (FLOAT heap kind)
- 06-typesystem &sect;8 (arithmetic operands must have same numeric type)
