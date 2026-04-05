# Raise Kestrel Exception for Task.race with Empty List

## Sequence: S06-08
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)

## Summary

Calling `Task.race([])` currently throws a raw Java `RuntimeException("no tasks provided")` that surfaces to Kestrel code as an untyped JVM crash rather than a catchable Kestrel exception. This prevents Kestrel code from handling the error with `try/catch` as it could for any other Kestrel exception.

## Current State

In `KTask.taskRace`, when the input list is empty:

```java
if (tasks.isEmpty()) {
    throw new RuntimeException("no tasks provided");
}
```

`RuntimeException` is not wrapped by the Kestrel exception propagation mechanism, so it cannot be caught by a Kestrel `try/catch` block.

## Relationship to other stories

- S06-06: companion fix in the async correctness batch.
- S06-10: spec documentation for `Task.race` error semantics.
- S06-11: test coverage for this edge case (catch in Kestrel `try/catch`).

## Goals

- `Task.race([])` raises an exception that Kestrel code can catch with the normal `try/catch` mechanism.
- The exception type has a meaningful name visible in Kestrel (e.g. the message "no tasks provided" surfaced as a Kestrel `Error` or a dedicated exception).

## Acceptance Criteria

1. [x] `try { await Task.race([]) } catch { e => ... }` catches the error in Kestrel without a JVM stack trace.
2. [x] The caught exception has a readable message ("no tasks provided" or equivalent).
3. [x] All existing `Task.race` tests continue to pass.
4. [x] A new conformance test exercises the empty-list catch path.

## Spec References

- `docs/specs/02-stdlib.md` — `Task.race` entry (once documented; see S06-10)

## Risks / Notes

- Need to identify the correct Kestrel exception class / wrapping mechanism used elsewhere when Java exceptions cross the JVM→Kestrel boundary.
- If Kestrel uses a `KException` wrapper, wrapping the `RuntimeException` should be a one-liner.
- The empty-list scenario is a programming error, so a runtime error (not a typed `Result`) is the right choice.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `KTask.java` `taskRace()` empty-list path — change `new RuntimeException(...)` to `new KException("no tasks provided")` so it flows through `normalizeCaught` and becomes catchable |
| Tests | Add a Kestrel test that catches `Task.race([])` without JVM crash |

## Tasks

- [x] In `KTask.java` `taskRace()` empty-list branch: change `new RuntimeException("Task.race called with empty list")` to `new KException("no tasks provided")`
- [x] Add a Kestrel test that does `try { await Task.race([]) } catch { e => 1 }` and asserts the catch fires
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `tests/unit/async_virtual_threads.test.ks` | `Task.race([])` is caught without JVM crash; caught value is non-null |

## Documentation and specs to update

None — S06-10 will document `Task.race` error semantics.

## Build notes

- 2026-04-05: Changed `failed.completeExceptionally(new RuntimeException(...))` to `new KException("no tasks provided")`. `KException` is a `RuntimeException` subclass that `normalizeCaught` recognises and returns its payload; `unwrapFailure` returns it as-is (it's not an ExecutionException/CompletionException and `KException.class != RuntimeException.class`). Added `raceEmptyResult` test in `async_virtual_threads.test.ks`: catches the empty-list error and asserts result == 1. 1072 Kestrel tests pass.
