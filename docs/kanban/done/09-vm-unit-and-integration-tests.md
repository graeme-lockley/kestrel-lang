# VM Unit and Integration Tests

## Sequence: 09
## Tier: 2 — Harden the runtime
## Former ID: 100

## Summary

The VM has essentially no meaningful tests. There are only a few trivial Zig tests (placeholder, value size, minimal .kbc load). No tests exist for systematic opcode execution, GC correctness, closure handling, record operations, ADT matching, exception handling, or multi-module loading. This makes it difficult to refactor or fix VM bugs with confidence.

## Current State (completed)

- **`main.zig`:** `test { ... }` block imports all VM modules so `zig build test` runs tests from `value`, `load`, `exec`, `gc`, `primitives`, and `vm_bytecode_tests`.
- **`exec.run`** accepts optional `out_top` for bytecode tests to assert the operand stack top after outermost `RET`.
- **`vm/src/vm_bytecode_tests.zig`:** Hand-crafted bytecode covering arithmetic, comparisons, control flow, records, ADT `CONSTRUCT`/`MATCH`, `LOAD_FN`/`MAKE_CLOSURE`/`CALL_INDIRECT`, and `TRY`/`THROW`/`END_TRY`.
- **`vm/test/fixtures/`:** `empty.kbc` (minimal valid module, single `RET`) and `minimal_main.kbc` (compiler-generated sample with non-empty function table and constant pool).
- **`value.zig` / `gc.zig`:** Extended tests for 61-bit int extrema, tag round-trips, and mark/sweep freeing unmarked heap objects.

## Acceptance Criteria

- [x] **Value tests**: Tag encoding/decoding for int, bool, unit, char, ptr, fn_ref. Boundary values (max/min 61-bit int).
- [x] **Arithmetic tests**: ADD, SUB, MUL, DIV, MOD, POW with various int values. Edge cases (zero, negative, large).
- [x] **Comparison tests**: EQ, NE, LT, LE, GT, GE for ints and bools.
- [x] **Control flow tests**: JUMP, JUMP_IF_FALSE with hand-crafted code buffers.
- [x] **Record tests**: ALLOC_RECORD, GET_FIELD, SET_FIELD, SPREAD.
- [x] **ADT tests**: CONSTRUCT, MATCH dispatch by constructor tag.
- [x] **Closure tests**: LOAD_FN, MAKE_CLOSURE, CALL_INDIRECT for both fn_ref and closure.
- [x] **Exception tests**: TRY, THROW, END_TRY — handler invocation, normal completion, uncaught failure.
- [x] **GC tests**: Mark/sweep frees unrooted objects while keeping marked allocations (see `gc.zig`). Full “pressure” GC during `run` remains covered indirectly by Kestrel programs and can be extended later.
- [x] **Loader tests**: `empty.kbc` plus `minimal_main.kbc` (non-empty functions and constants).
- [x] Fixtures are hand-crafted bytes on disk and in-test module construction.

## Tasks

- [x] Register VM module tests from `main.zig`; add `vm_bytecode_tests.zig` and fixtures.
- [x] Extend `value`, `load`, `exec`, `gc` tests; optional `exec.run` result hook for assertions.
- [x] Update specs (`08-tests` §2.4) and verify `zig build test`, compiler tests, `./scripts/kestrel test`, E2E.

## Related

- Sequence **25** (VM test fixtures) is a smaller, fixture-focused slice; prefer folding fixture work into this story unless splitting helps incremental delivery.

## Spec References

- [08-tests.md](../../specs/08-tests.md) §2.4 (Bytecode and VM), §2.5 (Runtime model / GC)
