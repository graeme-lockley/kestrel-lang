# Type checker: Unit tests and conformance verification

## Description

IMPLEMENTATION_PLAN Phase 2.5 lists deliverables as [ ]: type checker unit tests (unification, inference, exhaustiveness, async, exceptions); conformance tests pass/fail with asserted messages; integration tests for parse+typecheck.

The type checker exists and conformance tests exist (`tests/conformance/typecheck/valid/` and `invalid/`). Verify that:
1. All conformance tests run and pass/fail as expected
2. Dedicated unit tests exist for unification, generalise/instantiate, exhaustiveness, async context, exception typing
3. Integration tests parse then typecheck multi-declaration programs

## Acceptance Criteria

- [ ] Compiler test suite runs typecheck conformance tests (valid pass, invalid fail with expected message)
- [ ] Unit tests for: unify success/failure, generalise/instantiate, checkExhaustive, await outside async, throw exception type
- [ ] Integration test: parse + typecheck multi-declaration program
- [ ] Update IMPLEMENTATION_PLAN Phase 2.5 checkboxes if already done
