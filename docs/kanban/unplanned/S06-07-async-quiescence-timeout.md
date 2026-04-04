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

1. When all async tasks complete normally, the process exits with the existing behavior (no timeout printed).
2. When `kestrel.exitWaitTimeoutMs` is unset, a reasonable default (e.g. 30 000 ms) is used.
3. When `kestrel.exitWaitTimeoutMs=0`, the timeout is disabled (existing infinite-wait behavior).
4. When a task is stuck past the deadline, the process prints the warning to stderr and exits with code 1.
5. All existing async tests pass with the new code in place.

## Spec References

- `docs/specs/01-language.md` — async execution model section
- `docs/specs/02-stdlib.md` — `Task` section (see also S06-10 for spec additions)

## Risks / Notes

- The `wait(long timeout)` overload in Java uses milliseconds; care needed for the deadline-loop pattern to handle spurious wake-ups correctly.
- Setting a default too low could break slow CI environments; 30 s is conservative.
- `kestrel.exitWaitTimeoutMs=0` escape hatch prevents regressions in any environment that relies on the legacy infinite-wait behavior.
