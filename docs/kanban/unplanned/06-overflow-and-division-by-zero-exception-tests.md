# Overflow and Division-by-Zero Exception Tests

## Sequence: 06
## Tier: 2 — Harden the runtime
## Former ID: 101

## Summary

The unit test file `tests/unit/overflow_divzero.test.ks` exists but all tests are commented out. Integer overflow and division-by-zero are supposed to throw runtime exceptions that can be caught with `try/catch`. These tests need to be uncommented, fixed if necessary, and passing.

## Current State

- `tests/unit/overflow_divzero.test.ks`: all test bodies are commented out.
- The VM (`exec.zig`) does implement overflow detection on ADD/SUB/MUL and division-by-zero on DIV/MOD, throwing runtime exceptions.
- No active test exercises these code paths.

## Acceptance Criteria

- [ ] Uncomment and fix `overflow_divzero.test.ks` so all tests pass.
- [ ] Tests cover: addition overflow, subtraction overflow, multiplication overflow, division by zero, modulo by zero.
- [ ] Each test uses `try/catch` to verify the exception is catchable.
- [ ] `./scripts/kestrel test` passes with these tests active.

## Spec References

- 01-language (exception handling)
- 05-runtime-model (integer overflow, division by zero → runtime exception)
