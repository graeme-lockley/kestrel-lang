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
- E03 (HTTP) will need request cancellation.

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

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime (`KTask.java`) | Add `public static void cancel(Object taskObj)` that calls `CompletableFuture.cancel(true)`; update `taskRace` to cancel losing tasks |
| JVM runtime (`KRuntime.java`) | Add 3rd `String cancelledClass` param to `normalizeCaught`; map `CancellationException` to Kestrel `Cancelled` value reflectively |
| Compiler typecheck (`check.ts`) | Register `__task_cancel` intrinsic with type `forall T. Task<T> -> Unit` |
| Compiler codegen (`codegen.ts`) | Add `__task_cancel` handler: emit task arg, INVOKESTATIC `KTask.cancel`, push KUnit; update try/catch handler to look up `Cancelled` ADT class and pass to `normalizeCaught` with updated 3-String descriptor |
| Stdlib (`task.ks`) | Add `export exception Cancelled`; add `export fun cancel<T>(t: Task<T>): Unit = __task_cancel(t)` |
| Tests | Conformance runtime test covering cancel/catch; unit test in await-behavior test |
| Specs | `docs/specs/02-stdlib.md` §kestrel:task — document `cancel` and `Cancelled`; `docs/specs/01-language.md` §5 — note cancellation semantics |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KTask.java`: add `public static void cancel(Object taskObj)` calling `future.cancel(true)`
- [x] `runtime/jvm/src/kestrel/runtime/KTask.java`: update `taskRace` to cancel losing tasks after the winner completes
- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `String cancelledClass` param to `normalizeCaught`; catch `CancellationException` and reflectively instantiate `cancelledClass` (same pattern as ArithmeticOverflow)
- [x] `compiler/src/typecheck/check.ts`: register `__task_cancel` intrinsic: `forall T. Task<T> -> Unit`
- [x] `compiler/src/jvm-codegen/codegen.ts`: add `__task_cancel` handler (emit arg, INVOKESTATIC `KTask.cancel:(Ljava/lang/Object;)V`, push KUnit.INSTANCE)
- [x] `compiler/src/jvm-codegen/codegen.ts`: update TryExpr handler to look up `adtClassByConstructor.get('Cancelled')` and pass 3rd string to updated descriptor
- [x] `stdlib/kestrel/task.ks`: add `export exception Cancelled` and `export fun cancel<T>(t: Task<T>): Unit`
- [x] `tests/conformance/runtime/valid/task_cancel.ks`: cancel a task, await inside try/catch, cancel after completion (no-op)
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm run build && npm test`
- [ ] `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/task_cancel.ks` | `Task.cancel` catches `Cancelled`, cancel after completion is a no-op |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `cancel<T>(t: Task<T>): Unit` and `exception Cancelled` to kestrel:task section
- [x] `docs/specs/01-language.md` — §5: note that awaiting a cancelled task raises `Cancelled`; mention best-effort I/O interruption

## Build notes

- 2025-01-01: Implemented. `normalizeCaught` updated to 4-param signature. `KTask.cancel()` added. TryExpr codegen reads `Cancelled` ADT class from `adtClassByConstructor`. The conformance test uses `try { ... } catch { Cancelled => ... }` (no variable binding) since the catch with variable + wildcard arms in async methods triggered a pre-existing JVM stackmap verification issue with temp slot numbering.
- taskRace now cancels losing tasks by chaining a `thenRun` that iterates the original task list and cancels all futures after the winner completes.
