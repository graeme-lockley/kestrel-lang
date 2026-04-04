# Add Cycle Detection to KTask.unwrapFailure

## Sequence: S06-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)

## Summary

`KTask.unwrapFailure()` walks a chain of `ExecutionException` causes in a `while` loop to peel off wrapper exceptions and surface the original error. The loop has no depth limit or cycle guard. A pathological exception chain where a cause eventually points back to an ancestor would cause an infinite loop and hang the JVM thread.

## Current State

```java
private static Throwable unwrapFailure(Throwable t) {
    while (t instanceof ExecutionException && t.getCause() != null) {
        t = t.getCause();   // ← no depth limit, no visited-set
    }
    return t;
}
```

While circular `Throwable` chains are extremely rare in practice (Java's exception infrastructure does not create them), they are possible with reflection or adversarial code and represent an availability risk if they ever occur.

## Relationship to other stories

- Low-risk hardening companion to S06-06, S06-07, S06-08 in the async safety batch.

## Goals

- `unwrapFailure` terminates after a bounded number of iterations regardless of the exception chain structure.
- The bound is generous enough to be invisible in normal use (e.g. 64 iterations).
- When the limit is hit, the last seen `Throwable` is returned rather than throwing a secondary error.

## Acceptance Criteria

1. `unwrapFailure` with a chain of 1 000 nested `ExecutionException` wrappers terminates and returns a non-null value.
2. Normal usage (chains of depth 1–5) is unaffected.
3. All existing tests pass.

## Spec References

- (Internal implementation detail; no spec reference required.)

## Risks / Notes

- The chosen depth limit (64) is arbitrary but safe; document it as a constant.
- Returning the last seen `Throwable` at the limit is preferable to throwing a new error, to avoid masking the original failure.
- A `HashSet<Throwable>` visited set would be more precisely correct but is unnecessary overhead for a depth limit of 64.
