# Task Cancellation API

## Sequence: S01-17
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

`KTask` wraps a `CompletableFuture<Object>` but `CompletableFuture.cancel()` is never exposed to Kestrel code. There is currently no way to cancel an in-progress `Task`. For I/O tasks (file reads, process waits, HTTP requests) that conceptually should be cancellable, a hung or slow task must run to completion or until the JVM exits. This story exposes a `Task.cancel` function and the underlying `CancellationException` as a catchable ADT value.

## Current State

- `KTask.java` exposes only `get()` (blocking) and `completed()` (factory).
- `CompletableFuture.cancel(true)` is available but not called from Kestrel.
- `--exit-no-wait` is the only way to abandon running tasks.
- `Task<T>` type has no member functions accessible from Kestrel.

## Relationship to other stories

- Depends on S01-01 (KTask runtime class).
- S01-13 (Task combinators) — `Task.race` should cancel losing tasks; this story must be done first or concurrently for full `race` semantics.
- E02 (HTTP) will need request cancellation.

## Goals

1. `KTask.cancel()` calls `CompletableFuture.cancel(true)` on the underlying future.
2. A stdlib function `Task.cancel(t: Task<T>): Unit` (or similar surface form) is accessible from Kestrel code.
3. Awaiting a cancelled task raises a catchable `Cancelled` exception (a Kestrel ADT or a named error).
4. The cancellation propagates correctly to the underlying virtual thread if it is blocked on I/O.
5. Tests cover: cancel before completion, cancel after completion (no-op), and catching `Cancelled` through `try/catch`.

## Acceptance Criteria

- `Task.cancel(t)` compiles and runs without error.
- Awaiting a cancelled task inside `try { ... } catch { Cancelled => ... }` catches correctly.
- Cancelling an already-completed task is a no-op (no exception).
- Unit or conformance tests cover the above.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- `docs/specs/01-language.md` §5 — add cancellation semantics.
- `docs/specs/02-stdlib.md` — document `Task.cancel` and `Cancelled`.

## Risks / Notes

- `CompletableFuture.cancel(true)` sets the interrupt flag on blocked threads but does not guarantee I/O interruption on every JVM implementation. Document the best-effort nature.
- Deciding whether `Task.cancel` is a method, a free function, or a builtin affects how the type checker and codegen expose it. A free function in `kestrel:task` is least invasive.
- `CancellationException` from Java needs to be mapped to a Kestrel-visible error — either a new stdlib ADT `type TaskError = Cancelled | ...` or a catch-all exception pattern.
