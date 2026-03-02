# VM: Float as first-class value

## Description

Per spec 01 §2.7 and 05 §1–§2, Float is a 64-bit IEEE 754 type that is **boxed** at runtime (PTR to FLOAT heap object). Currently the VM has no FLOAT heap kind and no Float tag in the value representation; `value.zig` only has int, bool, unit, char, ptr, fn_ref. Float appears only inside the JSON Value ADT in primitives. Implement Float as a first-class value: constant pool tag Float → allocate FLOAT heap object and push PTR; arithmetic ops (ADD, SUB, MUL, DIV, etc.) should accept Float operands and produce Float results where specified by the language.

## Acceptance Criteria

- [ ] Add FLOAT heap object kind in `vm/src/gc.zig` (and any header/layout used by exec.zig)
- [ ] Loader: when constant pool entry has Float tag, allocate a FLOAT heap object, push Value.ptr() to it
- [ ] In `vm/src/exec.zig`, extend arithmetic instructions to handle Float operands (both Int and Float; spec 01/06: operands must have same numeric type, result that type)
- [ ] Ensure GC traces and retains FLOAT objects
- [ ] E2E or runtime conformance test: float literal and float arithmetic (e.g. `val x = 1.0`; `x + 2.0`) runs and produces correct output

## Notes

- Unplanned story `docs/kanban/unplanned/vm-float-support.md` overlaps; this backlog story aligns with the language-spec review.
