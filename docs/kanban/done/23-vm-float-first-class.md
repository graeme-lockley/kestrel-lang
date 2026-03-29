# VM Float as First-Class Value


## Sequence: 23
## Former ID: 20
## Priority: 20 (Critical)

## Summary

Float is specified as a boxed heap value (spec 05 §1, §2) but was completely non-functional in the VM. Loading a Float constant produced `Value.unit()`. No float arithmetic, comparison, or heap allocation existed. This blocked any program that uses floating-point numbers.

## Current State (completed)

- **Constant pool loader** (`load.zig`): Reads Float entries (tag 1) and allocates FLOAT blocks (Option A), tracked in `float_objects`, freed in `freeModule`.
- **FLOAT_KIND** in `gc.zig`: value 6; `allocFloat(f64)` implemented; explicit FLOAT in mark.
- **Arithmetic ops** (ADD, SUB, MUL, DIV, MOD, POW): Handle both int and ptr-to-FLOAT; float results boxed via `gc.allocFloat`.
- **Comparison ops** (EQ, NE, LT, LE, GT, GE): Support float operands (and NaN semantics).
- **JSON**: Value.Float uses FLOAT heap object; stringify reads f64 from heap. `formatInto` formats FLOAT as decimal.
- **Compiler**: Type checker allows Int or Float for arithmetic (spec 06 §8); codegen unchanged.

## Acceptance Criteria

- [x] Add `FLOAT_KIND` constant to `gc.zig` (e.g., value 6).
- [x] Implement `allocFloat(f64)` in `gc.zig` -- allocates a heap object with kind FLOAT, stores the f64 payload.
- [x] Update `load.zig` to allocate FLOAT for constant pool tag 1 instead of returning `Value.unit()` (Option A: allocator-allocated blocks).
- [x] Arithmetic instructions (ADD, SUB, MUL, DIV, MOD, POW) support both int and ptr-to-FLOAT; same numeric type per spec 06 §8.
- [x] Comparison instructions (EQ, NE, LT, LE, GT, GE) support float operands.
- [x] GC mark phase traces FLOAT objects (no child pointers).
- [x] `formatInto` in `primitives.zig` formats FLOAT heap objects as decimal.
- [x] JSON Value.Float uses proper FLOAT heap objects; removed @bitCast hack.
- [x] E2E test: `tests/conformance/runtime/valid/float_ops.ks` with float literals, arithmetic, comparison, print.
- [x] Kestrel unit test: `tests/unit/float.test.ks` covering float operations.

## Tasks

- [x] Add `FLOAT_KIND` and `FLOAT_HEADER` to gc.zig; implement `allocFloat`; add explicit FLOAT in mark.
- [x] load.zig: for constant pool tag 1, allocate FLOAT block (Option A), track in float_objects, free in freeModule.
- [x] exec.zig: value→f64 helper, both-float detection; extend ADD/SUB/MUL/DIV/MOD/POW and EQ/NE/LT/LE/GT/GE for floats.
- [x] primitives.zig: formatInto handle FLOAT_KIND; JSON Value.Float use FLOAT heap, stringify read f64 from heap.
- [x] E2E float program and tests/unit/float.test.ks; run full test suite.
- [x] Move story to done.

## Spec References

- 01-language §2.7 (Float literals)
- 03-bytecode-format §5 (Constant pool Float tag 1)
- 05-runtime-model §1 (Float is always boxed), §2 (FLOAT heap kind)
- 06-typesystem §8 (arithmetic operands must have same numeric type)
