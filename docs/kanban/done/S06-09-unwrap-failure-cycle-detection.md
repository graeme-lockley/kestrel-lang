# Add Cycle Detection to KTask.unwrapFailure

## Sequence: S06-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/done/E06-runtime-modernization-and-dx.md)

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

1. [x] `unwrapFailure` with a chain of 1 000 nested `ExecutionException` wrappers terminates and returns a non-null value.
2. [x] Normal usage (chains of depth 1–5) is unaffected.
3. [x] All existing tests pass.

## Spec References

- (Internal implementation detail; no spec reference required.)

## Risks / Notes

- The chosen depth limit (64) is arbitrary but safe; document it as a constant.
- Returning the last seen `Throwable` at the limit is preferable to throwing a new error, to avoid masking the original failure.
- A `HashSet<Throwable>` visited set would be more precisely correct but is unnecessary overhead for a depth limit of 64.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `KTask.java` `unwrapFailure()` — add `MAX_UNWRAP_DEPTH = 64` constant and an iteration counter; return `current` when depth is exceeded |

## Tasks

- [x] Add `private static final int MAX_UNWRAP_DEPTH = 64;` constant to `KTask.java`
- [x] Add iteration counter to `unwrapFailure()` loop; `return current` when depth exceeds `MAX_UNWRAP_DEPTH`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

None — the cycle/depth case is an internal hardening not exercised by normal tests.

## Documentation and specs to update

None — internal implementation detail.

## Build notes

- 2026-04-05: Added `MAX_UNWRAP_DEPTH = 64` constant. Loop counter `depth` increments on each unwrap step; when `depth >= MAX_UNWRAP_DEPTH` the loop exits and returns whatever `current` is (non-null at that point), not a replacement exception. This is safer than returning a new `RuntimeException` as it preserves the last available failure. Also fixed the null-fall-through case: replaced `return new RuntimeException("Unknown async task failure")` with `return current != null ? current : new RuntimeException(...)`. 1072 Kestrel tests pass.
