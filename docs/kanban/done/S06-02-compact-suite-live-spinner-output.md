# Test output: stable multi-mode harness with asyncGroup and async leak fixes

## Sequence: S06-02
## Tier: Optional / verification — Test harness UX
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/done/E06-runtime-modernization-and-dx.md)
- Companion stories: 67, 72

## Summary

Overhaul the `kestrel test` harness for stability and correctness across all three output modes (compact, verbose, summary). The original scope included a live spinner with in-place TTY updates; through joint design decisions this was dropped in favour of simpler, more reliable output. The final delivery covers: suite-first output in all modes, an `asyncGroup` primitive that allows async assertions inside group bodies, async task leak fixes in the JVM runtime, and a two-phase test runner that streams output incrementally rather than buffering it until subprocess exit.

## Current State (at story start)

- `kestrel test` captured all runner stdout in a subprocess; output was lost on crash.
- `kestrel:test` printed child assertion lines before the suite header in compact mode (visually inverted).
- `group()` accepted only sync callbacks — all async work had to be hoisted before calling `group`.
- Async leaks: `CompletableFuture.cancel(true)` did not interrupt blocked virtual threads; the 30-second quiescence timeout fired on every `Task.race` test run.
- `SPINNER` and `CLEAR_LINE` constants existed in `console.ks` from an earlier iteration but were unused.

## Goals

1. Suite header appears before child output in all three modes. ✓
2. `asyncGroup` primitive lets test bodies use `await` naturally. ✓  
3. Exception thrown inside an async body records a failure and continues sibling groups. ✓
4. Async task leaks (virtual thread not interrupted on cancel) are fixed. ✓
5. `printSummary` reports how many async tasks are still in flight when tests finish. ✓
6. Test runner streams output incrementally (not buffered). ✓

## Acceptance Criteria

- [x] Compact mode prints suite headers before child assertion output.
- [x] Verbose mode prints suite headers before child assertion output with per-assertion detail.
- [x] Summary mode prints one `name (N✓ Tms)` line per top-level suite.
- [x] `asyncGroup(s, name, async (sg) => { ... })` is callable from an `async fun run()`.
- [x] Exception inside an `asyncGroup` body records a failure and lets sibling groups continue.
- [x] Cancelled tasks (`Task.race` losers, `Task.cancel`) no longer leak into the quiescence counter.
- [x] `printSummary` appends `(N async task(s) still in flight)` when the count is non-zero.
- [x] `kestrel test` streams output live (exec model, not subprocess capture).
- [x] Failure output remains complete; failure expansion in compact mode prints diagnostics.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:test` output mode contract and `group` / `asyncGroup` / `printSummary`.
- `docs/specs/08-tests.md` — test harness coverage context.
- `docs/specs/09-tools.md` — `kestrel test` output behavior and mode descriptions.

## Impact Analysis (actual)

- `runtime/jvm/src/kestrel/runtime/KRuntime.java`
  - `isTtyStdout()` added (existed, kept for `basics.ks` binding).
  - `getAsyncTasksInFlight()` added — returns current in-flight count.
  - `submitAsync()` — registers cancel listener that interrupts the virtual thread.
  - `runProcessAsync()` — registers cancel listener that destroys the OS process AND interrupts the thread.
- `runtime/jvm/src/kestrel/runtime/KTask.java`
  - `KTask.get()` — on `InterruptedException`, cancels the future and throws `CancellationException` so the quiescence counter decrements promptly.
- `stdlib/kestrel/task.ks` — `asyncTasksInFlight(): Int` extern added.
- `stdlib/kestrel/console.ks` — `YELLOW` constant added.
- `stdlib/kestrel/test.ks`
  - `Suite` type: removed `isTty`/`spinnerActive` (spinner dropped); kept `compactExpanded`.
  - `makeRoot(output)` factory — replaces direct `Suite` construction in generated runner.
  - `group()` refactored: prologue/epilogue extracted as private helpers shared with `asyncGroup`.
  - `asyncGroup()` added: accepts `(Suite) -> Task<Unit>`, wraps body in try/catch.
  - `printSummary(Suite)` — appends async-in-flight count via `asyncTasksInFlight()`.
  - Import of `asyncTasksInFlight` from `kestrel:task` added.
- `scripts/run_tests.ks`
  - `--generate` flag: writes `.kestrel_test_runner.ks` and exits without running it.
  - Atomic write (temp file + `cmp`) to avoid unnecessary recompilation.
- `scripts/kestrel` (`_run_unit_tests`)
  - Two-phase: Phase 1 generates the runner (fast, captured); Phase 2 `exec`s the runner directly so stdout is inherited.
  - `--clean`, `--refresh`, `--allow-http` flags now threaded through both phases.
- `docs/specs/02-stdlib.md` — `asyncGroup`, `printSummary` async diagnostic documented.
- `docs/specs/09-tools.md` — output mode descriptions and new flags documented.

## Tasks

- [x] Add `isTtyStdout()` to `KRuntime.java`
- [x] Add `isTtyStdout` extern to `basics.ks`
- [x] Add `SPINNER` and `CLEAR_LINE` to `console.ks`
- [x] Rewrite `test.ks`: remove spinner/isTty, add `makeRoot`, new `group()` / `asyncGroup()` behaviour
- [x] Add `asyncTasksInFlight` count to `printSummary`
- [x] Add `getAsyncTasksInFlight()` to `KRuntime.java`; expose via `kestrel:task`
- [x] Fix `submitAsync` / `runProcessAsync` to interrupt virtual thread on cancel
- [x] Fix `KTask.get()` to propagate cancellation on `InterruptedException`
- [x] Add `--generate` mode to `run_tests.ks`
- [x] Restructure `_run_unit_tests` to two-phase (generate then exec)
- [x] Thread `--clean`, `--refresh`, `--allow-http` through `_run_unit_tests`
- [x] Add `YELLOW` to `console.ks`
- [x] Update `docs/specs/02-stdlib.md`
- [x] Update `docs/specs/09-tools.md`
- [x] Verify all tests pass

## Build notes

2026-03-07: Initial delivery with suite-first compact output and `makeRoot`/`printSummary(Suite)` refactor.

2026-04-05 (joint design decision): Spinner and in-place TTY update dropped after review. Consensus was that spinner complexity adds fragility with no meaningful benefit in CI or piped use. The `isTtyStdout` binding was kept (added for completeness in basics.ks) but is not used by `test.ks`. `SPINNER` and `CLEAR_LINE` remain in `console.ks` as available primitives for user code.

2026-04-05: Fixed async task leak. `CompletableFuture.cancel(true)` ignores `mayInterruptIfRunning` for virtual threads; three tasks leaked on every `async_virtual_threads.test.ks` run (slowTask race loser + two runProcessAsync threads). Fix: `submitAsync` and `runProcessAsync` now register a `whenComplete` cancel listener that calls `me.interrupt()` on the submitting thread. `KTask.get()` converts `InterruptedException` to `CancellationException` so the `finally` block fires immediately.

2026-04-05: Two-phase runner. The single-subprocess model buffered all stdout; an async crash (quiescence timeout) killed the process before any output was flushed. Phase 1 runs `run_tests.ks --generate` to write `.kestrel_test_runner.ks` (captured, fast). Phase 2 `exec`s the compiled runner directly so the JVM process IS the shell process and stdout is inherited.

2026-04-05: `asyncGroup` added. The sync `group` callback type `(Suite) -> Unit` prevented `await` at the assertion level. `asyncGroup` accepts `(Suite) -> Task<Unit>` and wraps the body in a `try/catch` so one test suite's exception cannot kill sibling groups.

2026-04-05: `printSummary` now reports `asyncTasksInFlight() - 1` (subtracts the main task itself) in yellow when non-zero, so leaked tasks are immediately visible rather than silently triggering a 30-second timeout.

## Tests to add

No new test files — existing `harness_output.test.ks` and `async_virtual_threads.test.ks` exercise the changes. The async leak fix is verified by `async_virtual_threads.test.ks` running to completion with zero leaked tasks.

## Docs to update

- `docs/specs/02-stdlib.md` — kestrel:test section (asyncGroup, printSummary async count) ✓
- `docs/specs/09-tools.md` — test output description, new flags ✓

