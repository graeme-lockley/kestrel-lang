# Negative E2E Test Suite

## Sequence: 51
## Tier: 5 — Test coverage and quality
## Former ID: 18

## Summary

The E2E test infrastructure (`scripts/run-e2e.sh`) supports negative tests but the `tests/e2e/scenarios/negative/` directory has very few actual test files. Negative tests verify that programs with errors (syntax, type, runtime) fail as expected.

## Current State

- `run-e2e.sh` iterates over `tests/e2e/scenarios/negative/*.ks`, compiling each and verifying that either compilation or execution fails.
- The `negative/` directory may contain only a `README.md` and one scenario; expand with many more.
- Conformance tests (`tests/conformance/typecheck/invalid/`) cover type errors at the compiler level.
- Gaps: runtime errors (uncaught exceptions, stack overflow), compile errors at the full pipeline, multi-module resolution failures.

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
  - Division by zero (coordinate with sequence **15** overflow/divzero unit tests)
  - Stack overflow (deeply recursive function)
  - Pattern match on unexpected ADT constructor (if possible)
- [ ] Each test file has a clear comment explaining what error is expected.
- [ ] `run-e2e.sh` reports pass/fail per test with the test name.
- [ ] All negative tests pass in `scripts/test-all.sh`.

## Spec References

- 08-tests §3.5 (Coverage goals: errors -- golden or conformance tests for expected compile and runtime errors)
