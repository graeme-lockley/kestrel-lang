# Negative E2E Test Suite

## Priority: 21 (Medium)

## Summary

The E2E test infrastructure (`scripts/run-e2e.sh`) supports negative tests but the `tests/e2e/scenarios/negative/` directory contains only a README -- no actual test files. Negative tests verify that programs with errors (syntax, type, runtime) fail as expected.

## Current State

- `run-e2e.sh` iterates over `tests/e2e/scenarios/negative/*.ks`, compiling each and verifying that either compilation or execution fails.
- The `negative/` directory has only a `README.md` documenting conventions.
- Conformance tests (`tests/conformance/typecheck/invalid/`) cover type errors at the compiler level.
- No E2E negative tests exist for: runtime errors (uncaught exceptions, stack overflow), compile errors caught at the .kbc level, or multi-module resolution failures.

## Acceptance Criteria

- [ ] **Compile failure tests** (at least 5):
  - Syntax error (malformed expression)
  - Type error (argument type mismatch)
  - Unknown import (module not found)
  - Non-exhaustive match
  - Duplicate export name
- [ ] **Runtime failure tests** (at least 5):
  - Uncaught exception (no try/catch)
  - Explicit `exit(1)`
  - Division by zero (once story 03 is done)
  - Stack overflow (deeply recursive function)
  - Pattern match on unexpected ADT constructor (if possible)
- [ ] Each test file has a clear comment explaining what error is expected.
- [ ] `run-e2e.sh` reports pass/fail per test with the test name.
- [ ] All negative tests pass in `scripts/test-all.sh`.

## Spec References

- 08-tests &sect;3.5 (Coverage goals: errors -- golden or conformance tests for expected compile and runtime errors)
