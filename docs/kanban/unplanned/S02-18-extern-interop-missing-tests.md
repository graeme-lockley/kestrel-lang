# `extern fun` / `extern import` — Missing E2E and Regression Tests

## Sequence: S02-18
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01 through S02-17

## Summary

Two significant test gaps were deferred during E02 delivery:

1. **No runtime regression test for primitive-returning `extern fun`**: the conformance test for `extern fun` (`tests/conformance/runtime/valid/extern_fun_non_parametric.ks`) exercises only `KRuntime` wrapper methods that return reference types. No test verifies `extern fun` to a plain JVM method whose return type is a primitive (`int`, `boolean`, `double`). This means the critical boxing bug described in S02-14 has no regression guard.

2. **No E2E test for the full Maven + `extern import` round-trip**: S02-12 build notes explicitly deferred a positive E2E scenario involving an actual downloaded jar. The existing Maven integration tests cover only the resolver mechanics and `.kdeps` sidecar emission; they never run the resulting program against a real Maven artifact. The full round-trip (download → compile with `extern import` → run → classpath injected from `.kdeps`) is untested end-to-end.

## Current State

- `tests/conformance/runtime/valid/extern_fun_non_parametric.ks` tests `KRuntime#stringLength` and `StringBuilder` (both return reference types). No primitive return type test exists.
- `compiler/test/integration/maven-kdeps.test.ts` tests sidecar emission and conflict detection but never compiles + runs a program that calls into a downloaded jar.
- The deferred E2E acceptance item from S02-12 (`a network-dependent positive E2E scenario that calls an API from a downloaded external jar`) is still open.

## Relationship to other stories

- **Depends on S02-14** for the primitive-return regression test to be meaningful (the test should pass after S02-14 is fixed). This story should be implemented together with or immediately after S02-14. The test file can be written as part of this story and will fail until S02-14 lands — making it a regression guard that pinpoints the bug.
- **Depends on S02-12, S02-13** for the Maven + `extern import` E2E test.

## Goals

1. Add a runtime conformance test that exercises `extern fun` to a JVM method returning a primitive (`int`) and one returning a `boolean`. These tests will fail until S02-14 is fixed, providing a clear regression guard.
2. Add a positive E2E test scenario: program that declares `import "maven:..."`, uses `extern import` to bind a class from the downloaded jar, calls a method on it, and prints the result. Expected output is captured in a `.expected` file. The test can use a well-known, stable, small Maven artifact (e.g. `org.apache.commons:commons-lang3`) and method (e.g. `StringUtils.capitalize`).
3. The E2E test is marked so that CI can skip it when `KESTREL_MAVEN_OFFLINE=1`, but must pass offline **once the artifact is cached** (i.e. it is not inherently flaky for a warm cache).

## Acceptance Criteria

- [ ] `tests/conformance/runtime/valid/extern_fun_primitive_return.ks` exists and tests:
  - A method returning `int` (e.g. `String.length(): int` or `Math.abs(long):long` after S02-14).
  - A method returning `boolean` (e.g. `String.isEmpty(): boolean`).
- [ ] The runtime conformance test passes after S02-14 is complete.
- [ ] A positive E2E scenario exists under `tests/e2e/scenarios/positive/` that exercises the maven + `extern import` full pipeline.
- [ ] The E2E scenario passes when the Maven artifact is cached (`KESTREL_MAVEN_OFFLINE=1` after a prior warm-up run).
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- None — this story is purely tests; no spec changes are needed.

## Risks / Notes

- **Network-dependent test in CI**: the positive E2E maven test should be conditional on `KESTREL_MAVEN_OFFLINE` not being set. CI pipelines that run offline must pre-populate the cache or skip the test via the env flag. Document this in the E2E test's `README`.
- **Choosing the Maven artifact**: prefer a small, stable, widely-used artifact with no transitive dependencies. `commons-lang3` or `gson` are good candidates. Avoid artifacts with complex class hierarchies that would generate noisy sidecars.
- **Primitive return test should intentionally fail before S02-14**: write the test first (as a known-failing fixture) to enforce that S02-14 includes the regression guard. The test file should be placed in `tests/conformance/runtime/valid/` so it runs as part of the standard suite.
