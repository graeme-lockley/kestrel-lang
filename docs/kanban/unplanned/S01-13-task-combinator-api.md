# Task Combinator API (`all`, `race`, `map`)

## Sequence: S01-13
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

The only concurrency pattern currently available in Kestrel is "start tasks before any `await`, then await sequentially". There is no typed API for fan-out over a dynamic collection, racing tasks, or transforming a task's value without awaiting it. This story adds `Task.all`, `Task.race`, and `Task.map` combinators to the stdlib and JVM runtime, enabling idiomatic structured concurrency patterns.

## Current State

- `KTask` exposes only `get()` (blocking await).
- No stdlib module provides task combinators.
- Parallel fan-out over a `List<Task<T>>` requires manually iterating with `await` in a loop — sequential, not concurrent.
- The type `Task<T>` is first-class, but cannot be composed without explicit `await`.

## Relationship to other stories

- Depends on S01-01 (KTask runtime class).
- S01-17 (cancellation) is a natural follow-on — `race` should cancel the losers.
- E02 (HTTP/networking) will benefit directly from `Task.all` for parallel HTTP requests.

## Goals

1. **`Task.map`** — transform the result of a task without blocking: `Task.map(t, f)` returns a new `Task<B>` that applies `f` when `t` completes. No virtual thread needed (pure transform on the `CompletableFuture`).
2. **`Task.all`** — wait for all tasks in a `List<Task<T>>` to complete and collect results into `Task<List<T>>`. Fails fast if any task fails.
3. **`Task.race`** — return the result of the first task in a `List<Task<T>>` to complete. Remaining tasks continue running (or are cancelled if S01-17 is done).
4. Stdlib module `kestrel:task` (or additions to a suitable existing module) exposes these combinators.
5. The type checker and codegen support `Task` as a parameterised type argument to these functions.

## Acceptance Criteria

- `Task.map(t, f)` compiles, returns a `Task<B>`, and the mapped value is correct when awaited.
- `Task.all(tasks)` collects all results; if any task fails the outer task fails.
- `Task.race(tasks)` returns the first-completing value.
- At least one conformance or unit test exercises each combinator.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- `docs/specs/01-language.md` §5 (async semantics) — add combinator descriptions.
- `docs/specs/02-stdlib.md` — add `kestrel:task` module section.

## Risks / Notes

- `Task.all` and `Task.race` accept `List<Task<T>>` — this requires the type checker to handle polymorphic list iteration over a parameterised type. Verify that the existing generic machinery handles `List<Task<T>>` without extra work.
- `Task.race` semantics when the list is empty need a defined behaviour (e.g. reject with an error or return `Task<Option<T>>`).
- Cancellation of losing tasks in `race` is deferred to S01-17; document this in the spec.
