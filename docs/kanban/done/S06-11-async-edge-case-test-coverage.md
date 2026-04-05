# Async Edge-Case and Cross-Module Test Coverage

## Sequence: S06-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/done/E06-runtime-modernization-and-dx.md)

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

## Impact Analysis

- `tests/fixtures/async_helper.ks` — new file; exported `async fun` for cross-module async test.
- `tests/unit/async_virtual_threads.test.ks` — add import and four new test cases (AC1–AC4); AC5 already covered by S06-08.
- No runtime or compiler changes.

## Tasks

- [x] Create `tests/fixtures/async_helper.ks` with `export async fun asyncDouble`
- [x] Add `import * as AsyncHelper` to `async_virtual_threads.test.ks` and add `crossModule` computation (AC1)
- [x] Add `allFailed` computation for `Task.all` with two failing tasks (AC2)
- [x] Add `raceFailed` computation for `Task.race` with two failing tasks (AC3)
- [x] Add cancel-propagation-through-map computation (AC4)
- [x] Add group assertions for AC1–AC4

## Build notes

2026-03-07: All tests pass (exit code 0). AC5 (Task.race([]) try/catch) was already satisfied by S06-08; confirmed still present in the "Task.race" group.

- `Task.map` cancel propagation (AC4): source is `Process.runProcess("sh", ["-c", "sleep 10"])`; after `Task.cancel(mapped)`, `await slowSource` throws `Cancelled` immediately because the Java future is marked cancelled synchronously before `get()` is called. The OS process continues briefly but does not block the test.
- `Task.all` with `[fail(), fail()]` (AC2): both tasks throw `AsyncBoom` synchronously; `allOf` completes exceptionally with first failure; `await` rethrows as a Kestrel value caught by `_ => 1`.
- `Task.race` all-fail (AC3): same async exception; `anyOf` completes when first task fails; remaining task gets cancelled by `whenComplete`; caught by `_ => 1`.

## Tests to add

- All new tests live in `tests/unit/async_virtual_threads.test.ks`.
- New fixture: `tests/fixtures/async_helper.ks`.

## Docs to update

None — S06-10 already updated the specs.
