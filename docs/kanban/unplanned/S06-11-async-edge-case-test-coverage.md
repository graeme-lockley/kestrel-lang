# Async Edge-Case and Cross-Module Test Coverage

## Sequence: S06-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)

## Summary

Several important async/await scenarios have no test coverage: cross-module async calls, concurrent task failures in `Task.all`, all-fail behavior in `Task.race`, cancel propagation through `Task.map`, and catching the `Task.race([])` error in Kestrel. This story adds focused tests for each of these gaps to prevent regressions and confirm intended behavior.

## Current State

- `tests/unit/async_virtual_threads.test.ks` and `task.test.ks` cover the happy path and basic cancellation.
- No test imports an `async fun` from a separate module and `await`s it from another module.
- No test checks `Task.all` when multiple tasks fail concurrently.
- No test checks `Task.race` when every task fails.
- No test verifies that cancelling a `Task.map` result also cancels the source.
- No test catches the `Task.race([])` empty-list error in a Kestrel `try/catch`.

## Relationship to other stories

- S06-06: test confirms winning task is unaffected by the cancel loop.
- S06-07: (integration) a test with a stuck task verifies the timeout warning path.
- S06-08: test for `Task.race([])` caught in Kestrel.
- S06-10: spec entries that this story validates.

## Goals

- Each identified gap has at least one test in the appropriate test file.
- Cross-module async test lives in `tests/` as a multi-file scenario.
- All new tests pass and are included in the standard `./kestrel test` run.

## Acceptance Criteria

1. **Cross-module async**: a helper module exports an `async fun`; the main module imports and `await`s it; the test asserts the correct return value.
2. **Task.all concurrent failure**: two tasks that both fail return the first failure and cancel the remaining; the test asserts the caught exception is a Kestrel value (not a JVM stack trace).
3. **Task.race all-fail**: a `Task.race` where every competing task fails is caught and the exception is a Kestrel value.
4. **Cancel propagation through Task.map**: cancelling the mapped task causes the source task to also be cancelled (verified via a side-channel flag or by checking the source task's state).
5. **Task.race([]) in try/catch**: `try { await Task.race([]) } catch { e => println(e) }` runs without a JVM crash.
6. All existing async tests still pass.

## Spec References

- `docs/specs/01-language.md` — async/await
- `docs/specs/02-stdlib.md` — Task
- `docs/specs/07-modules.md` — §10 Async Exports and Cross-Module Async Calling

## Risks / Notes

- Cross-module test may require a new E2E scenario under `tests/e2e/scenarios/` if the existing unit test runner does not support multi-file imports.
- The `Task.race` all-fail case depends on understanding which exception surfaces (first? last? combined?); check `KTask.taskRace` before deciding the expected value.
- The stuck-task/timeout test (AC linked to S06-07) is optional here; it may need a special test-only system property to keep CI fast.
