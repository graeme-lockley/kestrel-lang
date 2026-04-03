# VM: Implement SPREAD instruction (0x19)


## Sequence: 49
## Former ID: (none)
## Description

Per spec 04 §1.8, the **SPREAD** opcode (0x19) pops a record and additional values from the stack and produces a new record with an extended shape for expressions like `{ ...r, x = v }`. The compiler already defines `Op.SPREAD` and `emitSpread()`, but the VM execution loop in `vm/src/exec.zig` does not handle opcode 0x19 (only 0x16–0x18 for ALLOC_RECORD, GET_FIELD, SET_FIELD). Add a SPREAD case so that when the compiler emits SPREAD, the VM executes it correctly.

## Acceptance Criteria

- [x] Add SPREAD (0x19) constant and case in `vm/src/exec.zig` execution loop
- [x] Implement semantics: pop record (PTR to RECORD) and N additional values in shape field order; allocate new record with extended shape from shape table; push PTR to new record
- [x] GC traces any new RECORD allocated by SPREAD
- [x] E2E or runtime conformance test that uses record spread and asserts correct result (once compiler emits SPREAD for spread literals)

## Tasks

- [x] Add SPREAD constant and case in vm/src/exec.zig
- [x] Add record spread group in tests/unit/records.test.ks (passes once compiler emits SPREAD)
- [x] Update docs/IMPLEMENTATION_PLAN.md, docs/specs/08-tests.md, docs/specs/04-bytecode-isa.md

## Notes

- Unplanned story `docs/kanban/unplanned/S05-01-vm-spread-instruction.md` covers follow-up verification; this done entry records the VM work. Compiler record spread codegen is a separate story (`38-compiler-record-spread-codegen.md`).
