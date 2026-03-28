# VM Operand Stack Overflow Guard

## Sequence: 08
## Tier: 2 — Harden the runtime
## Former ID: 86

## Summary

The VM operand stack is a fixed-size array of 4096 entries. Push operations (`stack[sp] = ...; sp += 1`) had no bounds check, so deeply recursive programs or malformed bytecode could silently write past the end of the array, causing undefined behavior. Call-frame overflow is already guarded; the operand stack needs the same treatment.

## Current State

- **Done:** `exec.zig` uses `pushOperand` before every operand push; overflow prints `Operand stack overflow (limit 4096 entries)` and a stack trace (same shape as uncaught exceptions, §5). VM tests cover helper saturation and `run()` with overflow bytecode.

## Acceptance Criteria

- [x] Add a bounds check before every operand push (via `pushOperand`), producing a clear "operand stack overflow" runtime error.
- [x] The error prints a stack trace reusing the uncaught-exception style (` at file:line` via debug section when present).
- [x] VM tests: `pushOperand` one-past-capacity; bytecode that issues `operand_stack_slots + 1` × `LOAD_CONST` then `RET` yields `run` failure.
- [x] Spec `docs/specs/05-runtime-model.md` updated (§1.3 operand/call limits; implementor summary).
- [x] Existing E2E and unit tests still pass (compiler, kestrel test, VM, e2e).

## Spec References

- 05-runtime-model (§1.3 stack limits; §5 stack traces)

## Tasks

- [x] Add `pushOperand` / `operandStackOverflowReport` and wire all operand pushes in `vm/src/exec.zig`
- [x] Add VM tests in `exec.zig`
- [x] Update `docs/specs/05-runtime-model.md`
- [x] Run verification: compiler tests, `./scripts/kestrel test`, `zig build test`, `./scripts/run-e2e.sh`
