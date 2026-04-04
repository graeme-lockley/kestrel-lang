# Fix Task.race to Only Cancel Losing Tasks

## Sequence: S06-06
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)

## Summary

`KTask.taskRace()` currently cancels **all** tasks in the input list once any one finishes — including the task that won the race. Because the winner's `CompletableFuture` is already completed, `cancel()` returns `false` and has no observable effect, but it violates clean semantics, makes the code misleading, and could interact badly with future Java versions that add `cancel()` post-completion behavior.

## Current State

In `KTask.java`, the `thenRun` callback inside `taskRace` iterates over all tasks and calls `t.future.cancel(true)` unconditionally:

```java
winner.thenRun(() -> {
    for (KTask t : tasksCopy) {
        t.future.cancel(true);   // ← cancels the winner too
    }
});
```

No guard checks whether a task is already done before attempting cancellation.

## Relationship to other stories

- See S06-07 for the related `awaitAsyncQuiescence` timeout fix.
- See S06-08 for empty-list handling in `Task.race`.
- Accompanies the broader async critical review findings (companion to S06-06 through S06-11).

## Goals

- The winner of a `Task.race` is never passed to `cancel()`; only genuinely in-flight losing tasks are cancelled.
- The fix is minimal: a single `isDone()` guard in the cancel loop.

## Acceptance Criteria

1. `Task.race` still resolves with the correct value.
2. Adding a `cancel()` call to a completed winner future is not reachable from the `thenRun` callback.
3. All existing async conformance and unit tests continue to pass.
4. A regression test confirms that `Task.race` cancels losing tasks and that the winning task's value is available.

## Spec References

- `docs/specs/02-stdlib.md` — `Task` section (once documented; see S06-10)

## Risks / Notes

- Low-risk, surgical change: add `if (!t.future.isDone())` before `cancel()`.
- No public API change; behavior is identical for all currently tested inputs.
