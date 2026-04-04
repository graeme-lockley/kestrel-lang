# Reduce `asyncTasksInFlight` Monitor Contention

## Sequence: S01-21
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

The `KRuntime` async quiescence mechanism uses a shared `Object asyncMonitor` and a plain `int asyncTasksInFlight` counter, both guarded by `synchronized(asyncMonitor)`. Every task start and every task completion acquires this monitor. At high parallelism — many short-lived tasks completing rapidly — this serializes every completion notification and can become a throughput bottleneck. `LongAdder` eliminates contention on the counter, and `Phaser` or a `CountDownLatch`-style mechanism is more appropriate for quiescence waiting than a raw `wait/notifyAll` spin loop.

## Current State

```java
// KRuntime.java
private static final Object asyncMonitor = new Object();
private static int asyncTasksInFlight = 0;

// on task submit:
synchronized (asyncMonitor) { asyncTasksInFlight++; }

// on task complete:
synchronized (asyncMonitor) { asyncTasksInFlight--; asyncMonitor.notifyAll(); }

// awaitAsyncQuiescence:
while (asyncTasksInFlight > 0) { asyncMonitor.wait(); }
```

## Relationship to other stories

- Depends on S01-02 (virtual thread executor infrastructure).
- Purely a `KRuntime.java` change; no Kestrel language or compiler changes needed.
- Relevant if S01-13 (Task.all/race) produces high volumes of concurrent tasks.

## Goals

1. Replace `int asyncTasksInFlight + synchronized(asyncMonitor)` with a `LongAdder` (or `AtomicLong`) for the counter — contention-free increment/decrement.
2. Replace the `wait/notifyAll` quiescence loop with a `Phaser` (or `CountDownLatch`-per-run) so that `awaitAsyncQuiescence` blocks efficiently rather than spinning.
3. Functional behaviour is identical: `runMain` with `--exit-wait` still waits for all tasks to complete before shutdown.
4. Thread-safety is maintained: no lost updates, no missed notifications.

## Acceptance Criteria

- Existing async tests pass with the new implementation.
- No `synchronized(asyncMonitor)` blocks remain on the hot completion path.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- No spec changes needed — this is a pure runtime internals change.

## Risks / Notes

- `Phaser` has more complex semantics than `wait/notifyAll`; a `CountDownLatch` per-run is simpler but requires knowing the final task count upfront (which we don't). `Phaser` with `arriveAndAwaitAdvance` is the idiomatic choice here.
- The `initAsyncRuntime` / `shutdownAsyncRuntime` lifecycle must remain thread-safe after the change; verify that executor shutdown and quiescence waiting interact correctly with the new counter.
- Performance improvement is most visible under micro-benchmark conditions; an existing correctness test suite is sufficient for acceptance.
