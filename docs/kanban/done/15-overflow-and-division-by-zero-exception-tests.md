# Overflow and Division-by-Zero Exception Tests

## Sequence: 15
## Tier: 2 — Harden the runtime
## Former ID: 10

## Summary

The unit test file `tests/unit/overflow_divzero.test.ks` exists but all tests are commented out. Integer overflow and division-by-zero are supposed to throw runtime exceptions that can be caught with `try/catch`. These tests need to be uncommented, fixed if necessary, and passing.

## Current State

- `tests/unit/overflow_divzero.test.ks` is active and passes under `./scripts/kestrel test`.
- VM unwinding to `try` handlers now restores the **handler’s module** (and globals when the try ran in module init), so catch works when code runs as an imported module.
- Compiler `try`/`catch` codegen emits all catch arms: constructor patterns use `CONSTRUCT` + `EQ` (deep equality) so distinct exception ADTs are not conflated; exception slot uses `nextLocalSlot`, not `Map.size`.

## Acceptance Criteria

- [x] Uncomment and fix `overflow_divzero.test.ks` so all tests pass.
- [x] Tests cover: addition overflow, subtraction overflow, multiplication overflow, division by zero, modulo by zero.
- [x] Each test uses `try/catch` to verify the exception is catchable.
- [x] `./scripts/kestrel test` passes with these tests active.
- [x] Impacted specs updated: `docs/specs/05-runtime-model.md` (§5 unwind / module), `docs/specs/08-tests.md` (§2.5 overflow/divzero inventory).

## Tasks

- [x] Uncomment and fix `tests/unit/overflow_divzero.test.ks` (syntax, exception names vs VM `allocRuntimeException`).
- [x] Run `./scripts/kestrel test` and fix any failures (VM `exec.zig` + compiler `codegen.ts`).
- [x] Update spec cross-references / `08-tests.md` and `05-runtime-model.md` §5.
- [x] Move story to `docs/kanban/done/` with criteria ticked.

## Spec References

- 01-language (exception handling)
- 05-runtime-model (integer overflow, division by zero → runtime exception)
