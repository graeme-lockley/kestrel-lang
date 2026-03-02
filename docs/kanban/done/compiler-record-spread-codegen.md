# Compiler: Record spread codegen

## Description

The language spec (01 §3.2) allows record literals with spread: `{ ...r, x = v }`. The parser and AST support it (`RecordExpr` with `spread`), but codegen explicitly skips this case (`if (expr.spread != null || !shapes) break` in the RecordExpr branch), so no SPREAD opcode is emitted and the expression effectively falls through. Implement codegen for RecordExpr when `expr.spread != null`: emit code for the spread record, then the new field values, compute the extended shape, and emit SPREAD (0x19) with the appropriate shape_id.

## Acceptance Criteria

- [x] In `compiler/src/codegen/codegen.ts`, handle `RecordExpr` when `expr.spread != null`
- [x] Emit operand(s) for the spread record and for each new field; ensure stack order matches 04 §1.8 (record first, then additional values in extended-shape field order)
- [x] Register or reuse shape for the extended record (base shape + new field names) and pass shape_id to `emitSpread(shapeId)`
- [x] Typecheck already allows record spread (row typing in 06 §2); no typecheck changes required unless gaps are found
- [x] Add unit or integration test: compile a program containing `{ ...r, x = v }` and verify SPREAD appears in emitted bytecode; add E2E or runtime conformance test once VM SPREAD is implemented

## Tasks

- [x] Implement RecordExpr spread branch in codegen (SPREAD path and override-only ALLOC_RECORD path)
- [x] Emit additional values first, then base record, then SPREAD (VM pops record first)
- [x] Add compiler unit test: record spread emits 0x19 and extended shape in compile.test.ts
- [x] Verify tests/unit/records.test.ks record spread group passes
- [x] Update docs/specs/08-tests.md, 04-bytecode-isa.md, 01-language.md; update IMPLEMENTATION_PLAN.md

## Dependencies

- VM must implement SPREAD (0x19) for E2E execution; see backlog story "VM: Implement SPREAD instruction (0x19)".
