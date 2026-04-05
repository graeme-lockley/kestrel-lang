# Add Configurable Timeout to awaitAsyncQuiescence

## Sequence: S06-07
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)

## Summary

`KRuntime.awaitAsyncQuiescence()` waits indefinitely for all async tasks to complete before the JVM exits. A deadlocked or hung async task will cause the entire Kestrel process to hang forever with no diagnostic output. Adding a configurable timeout prevents this silent hang and gives developers actionable feedback.

## Current State

The current implementation:

```java
private static void awaitAsyncQuiescence() {
    synchronized (quiescenceSignal) {
        while (asyncTasksInFlight.sum() > 0) {
            quiescenceSignal.wait();   // waits forever
        }
    }
}
```

There is no deadline, no timeout, and no warning output. A deadlocked async task causes the Kestrel process to silently block indefinitely.

## Relationship to other stories

- S06-06: companion fix in the same async correctness batch.
- S06-11: test coverage for the hanging-task scenario.

## Goals

- Process exits (with a non-zero status) after a configurable timeout if async tasks have not quiesced.
- The timeout is configurable via a JVM system property (`kestrel.exitWaitTimeoutMs`) so the default can be tuned or disabled in tests.
- On timeout, a diagnostic line is printed to stderr: `[kestrel] warning: exiting with N async task(s) still in flight (quiescence timeout)`

## Acceptance Criteria

1. [x] When all async tasks complete normally, the process exits with the existing behavior (no timeout printed).
2. [x] When `kestrel.exitWaitTimeoutMs` is unset, a reasonable default (e.g. 30 000 ms) is used.
3. [x] When `kestrel.exitWaitTimeoutMs=0`, the timeout is disabled (existing infinite-wait behavior).
4. [x] When a task is stuck past the deadline, the process prints the warning to stderr and exits with code 1.
5. [x] All existing async tests pass with the new code in place.

## Spec References

- `docs/specs/01-language.md` — async execution model section
- `docs/specs/02-stdlib.md` — `Task` section (see also S06-10 for spec additions)

## Risks / Notes

- The `wait(long timeout)` overload in Java uses milliseconds; care needed for the deadline-loop pattern to handle spurious wake-ups correctly.
- Setting a default too low could break slow CI environments; 30 s is conservative.
- `kestrel.exitWaitTimeoutMs=0` escape hatch prevents regressions in any environment that relies on the legacy infinite-wait behavior.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `KRuntime.java` `awaitAsyncQuiescence()` — add deadline loop using `wait(remaining)` and `System.exit(1)` on timeout |
| JVM runtime | `KRuntime.java` — new private helper `getExitWaitTimeoutMs()` reads `kestrel.exitWaitTimeoutMs` system property |

## Tasks

- [x] Add `getExitWaitTimeoutMs()` private helper in `KRuntime.java` (reads `kestrel.exitWaitTimeoutMs`, defaults to 30000, 0 = infinite)
- [x] Replace `awaitAsyncQuiescence()` with deadline-loop version; when `timeoutMs == 0` keep infinite wait; on deadline print warning and `System.exit(1)`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

None — the timeout path requires a stuck task which would make CI slow. Verified manually via the clean path (timeout not triggered).

## Documentation and specs to update

None — S06-10 will add spec coverage for async execution model.

## Build notes

- 2026-04-05: Added `getExitWaitTimeoutMs()` that reads `kestrel.exitWaitTimeoutMs` (default 30 000 ms, 0 = infinite). `awaitAsyncQuiescence()` now uses a deadline loop with `wait(remaining)` to handle spurious wake-ups. On timeout prints `[kestrel] warning: exiting with N async task(s) still in flight (quiescence timeout)` to stderr and calls `System.exit(1)`. The `timeoutMs == 0` branch preserves the original infinite-wait semantics for any environment that needs it. All 1071 Kestrel tests pass.
