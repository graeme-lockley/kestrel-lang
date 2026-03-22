# Stdlib kestrel:test Framework Completeness

## Sequence: 11
## Tier: 4 — Stdlib and test harness
## Former ID: 110

## Summary

The `kestrel:test` module provides a working test framework (`Suite`, `group`, `eq`, `printSummary`), but it could be extended with additional assertion types and better failure reporting to make tests more expressive and failures easier to diagnose.

## Current State

- `stdlib/kestrel/test.ks` provides:
  - `Suite` type with depth, summary flag, mutable pass/fail counters
  - `group(suite, name, body)` for nested grouping with timing
  - `eq(suite, description, actual, expected)` for equality assertions
  - `printSummary(counts)` for final results
- Only `eq` (equality) assertion exists. No `neq`, `isTrue`, `isFalse`, `throws`, `contains`, etc.
- Failure messages show expected vs actual but don't show types.
- No way to skip tests or mark them as expected-to-fail (xfail).

## Acceptance Criteria

- [ ] Add `neq(suite, desc, actual, notExpected)` -- assert not equal.
- [ ] Add `isTrue(suite, desc, value)` and `isFalse(suite, desc, value)` -- boolean assertions.
- [ ] Add `gt(suite, desc, actual, expected)`, `lt`, `gte`, `lte` -- numeric comparison assertions.
- [ ] Improve failure messages: show type information when types differ.
- [ ] Consider adding `throws(suite, desc, fn)` -- assert that calling `fn()` throws an exception (requires first-class function support in test context).
- [ ] Add `tests/unit/test_framework.test.ks` that tests the test framework itself (meta-test).

## Spec References

- 08-tests §3.5 (Coverage goals: test harness)
- 09-tools §2.4 (kestrel test command)
