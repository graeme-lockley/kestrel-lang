# Type checker: Unit tests and conformance verification


## Sequence: 48
## Former ID: (none)
## Description

**Specs:** [06-typesystem.md](../../specs/06-typesystem.md) (typing rules, §8 expression typing, §10 implementor checklist); [08-tests.md](../../specs/08-tests.md) (§2.2 Type Checker, §3.2 layout, §3.5 coverage goals). **Plan:** [IMPLEMENTATION_PLAN.md](../../IMPLEMENTATION_PLAN.md) Phase 2.5.

Phase 2.5 deliverables: type checker unit tests (unification, inference, exhaustiveness, async, exceptions); conformance tests pass/fail with asserted messages; integration tests for parse+typecheck — all done.

The type checker exists and conformance tests exist (`tests/conformance/typecheck/valid/` and `invalid/`). Verified that:
1. All conformance tests run and pass/fail as expected (08: invalid tests may assert a type error or error substring)
2. Dedicated unit tests exist for unification, generalise/instantiate, exhaustiveness, async context, exception typing (06 §5–§7, Plan 2.2–2.3)
3. Integration tests parse then typecheck multi-declaration programs (Plan 2.4–2.5)
4. Coverage matches 08 §3.5 and 06 §8: literals, conditionals, match (exhaustiveness), try/catch, lambdas, records, ADTs, pipelines, async/await; union/narrowing (08 §2.2); rejection tests for wrong arity, missing match case, unification/row failures

## Tasks

- [x] Identify all type checker unit and conformance test scenarios (map to 06 §8 and 08 §3.5)
- [x] Compiler test suite runs typecheck conformance tests (valid pass, invalid fail with expected message or substring per 08)
- [x] Unit tests for: unify success/failure, generalise/instantiate, checkExhaustive, await outside async, throw exception type
- [x] Verify (or add) tests for scenario categories: literals (bases, interpolation, chars), conditionals, match/exhaustiveness, try/catch, lambdas, records, ADTs, pipelines, async/await; union/narrowing (`is`, `A | B`, `A & B`)
- [x] Rejection tests: wrong arity, missing match case, unification failures, row conflicts (08 §2.2)
- [x] Integration test: parse + typecheck multi-declaration program
- [x] Ensure all type tests pass; fix or document any failures
- [x] Review test layout so typecheck tests are structured in a logical way (08 §3.2)
- [x] Update IMPLEMENTATION_PLAN Phase 2.5 checkboxes if already done

## Acceptance Criteria

- Test exists for all known typing scenarios per 06 §8 and 08 §3.5: literals, conditionals, match (exhaustiveness), try/catch, lambdas, records, ADTs, pipelines, async/await; union/narrowing; function call; statement; pattern matching.
- All type tests pass.
- The tests are structured in a logical way (conformance valid/invalid layout, clear scenario coverage).
