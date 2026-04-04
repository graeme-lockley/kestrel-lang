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

- [x] `tests/conformance/runtime/valid/extern_fun_primitive_return.ks` exists and tests:
  - A method returning `int` (e.g. `String.length(): int`).
  - A method returning `boolean` (e.g. `String.isEmpty(): boolean`).
- [x] The runtime conformance test passes after S02-14 is complete.
- [x] A positive E2E scenario exists under `tests/e2e/scenarios/positive/` that exercises the maven + `extern import` full pipeline.
- [x] The E2E scenario passes when the Maven artifact is cached; skipped when `KESTREL_MAVEN_OFFLINE=1`.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Tasks

- [x] Add `tests/conformance/runtime/valid/extern_fun_primitive_return.ks` with `strLen` (int return) and `strIsEmpty` (boolean return) tests
- [x] Fix `emitExternReturnAsObject` case `'I'` in codegen.ts: add `I2L` to widen int→long before boxing as Long (avoids Char/Int confusion in KRuntime.formatOne)
- [x] Fix `emitExternReturnAsObject` cases `'B'`, `'S'` similarly (byte/short → Long)
- [x] Add `// E2E_SKIP_OFFLINE` support to `scripts/run-e2e.sh` for network-dependent tests
- [x] Add `tests/e2e/scenarios/positive/maven-commons-lang3-capitalize.ks` + `.expected` (commons-lang3 `capitalize` full round-trip)
- [x] Run `cd compiler && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Spec References

- None — this story is purely tests; no spec changes are needed.

## Risks / Notes

- **Network-dependent test in CI**: the positive E2E maven test should be conditional on `KESTREL_MAVEN_OFFLINE` not being set. CI pipelines that run offline must pre-populate the cache or skip the test via the env flag. Document this in the E2E test's `README`.
- **Choosing the Maven artifact**: prefer a small, stable, widely-used artifact with no transitive dependencies. `commons-lang3` or `gson` are good candidates. Avoid artifacts with complex class hierarchies that would generate noisy sidecars.
- **Primitive return test should intentionally fail before S02-14**: write the test first (as a known-failing fixture) to enforce that S02-14 includes the regression guard. The test file should be placed in `tests/conformance/runtime/valid/` so it runs as part of the standard suite.

## Build notes

2025-01-01: Runtime conformance test `extern_fun_primitive_return.ks` uses `String#length():int` and `String#isEmpty():boolean`. Both pass after S02-14's `:ReturnType` suffix support.

2025-01-01: Fix discovered for `emitExternReturnAsObject` case `'I'`: the return value was boxed as `java.lang.Integer` but `KRuntime.formatOne(Integer)` treats `Integer` as `Char` (not `Int`), printing BEL character (U+0007) instead of the number. Fixed by adding `I2L` opcode + boxing as `Long`. Same fix applied to `B` (byte) and `S` (short) returns.

2025-01-01: E2E maven test uses `commons-lang3:3.17.0` (already in local cache from S02-12). Uses `extern import` to bind `StringUtils` and calls `capitalize("hello world")` → prints `"Hello world"`. E2E test tagged with `// E2E_REQUIRE_NETWORK` and skipped when `KESTREL_MAVEN_OFFLINE=1` is set. The `run-e2e.sh` skip mechanism checks for this tag. The `run-e2e.sh` also reports the count of skipped scenarios.

2025-01-01: 322 compiler tests + 1020 Kestrel tests + 12 negative + 11 positive E2E tests passing.
