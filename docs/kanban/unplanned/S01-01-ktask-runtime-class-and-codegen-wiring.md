# KTask JVM Runtime Class and Codegen Wiring

## Sequence: S01-01
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 22 (replaces monolithic async/await story)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-02, S01-03, S01-04, S01-05, S01-06, S01-07, S01-08, S01-09, S01-10, S01-11

## Summary

Introduce a concrete `KTask` Java class in the JVM runtime that wraps `CompletableFuture<Object>`, giving `Task<T>` a real runtime representation. Update `completedTask()` to return a `KTask` and update JVM codegen so `await` invokes `KTask.get()` instead of being transparent. No observable behavior change yet — all tasks remain completed synchronously — but the runtime plumbing is in place for virtual-thread-backed suspension in S01-02.

## Current State

- **`completedTask()`** in `KRuntime.java` wraps a value in an untyped `Object[]` tag (or similar ad-hoc wrapper); there is no dedicated Task class.
- **`await`** in `compiler/src/jvm-codegen/codegen.ts` is a no-op: `emitExpr(expr.value, mb, tcN)` — it just evaluates the inner expression.
- **`readFileAsync`** in `KRuntime.java` returns the payload directly (a `String`), not wrapped in any Task.
- No `CompletableFuture`, no virtual threads, no executor anywhere in the runtime.

## Relationship to other stories

- **Enables S01-02** (virtual thread executor): once KTask exists and codegen targets it, S01-02 adds the executor that backs KTask with real concurrency.
- **Enables S01-03** (non-blocking file I/O): `readFileAsync` will return a KTask instead of raw payload.
- **No external dependencies**: this story is self-contained and can be implemented first.

## Goals

1. **KTask class**: A Java class wrapping `CompletableFuture<Object>` with `completed(Object value)` factory and `get()` accessor.
2. **completedTask() update**: `KRuntime.completedTask()` returns a `KTask` whose future is already completed.
3. **Codegen wiring**: `AwaitExpr` emits `INVOKEVIRTUAL KTask.get()` (or equivalent static call) instead of being transparent.
4. **readFileAsync update**: Returns a `KTask.completed(payload)` instead of raw payload.
5. **Backward compatibility**: All existing async tests pass unchanged — the only difference is the intermediate `KTask` wrapper, which `get()` immediately unwraps for completed tasks.

## Acceptance Criteria

- [ ] `KTask.java` exists in `runtime/jvm/src/kestrel/runtime/` with `completed(Object)` and `get()` methods.
- [ ] `KRuntime.completedTask(Object)` returns a `KTask` instance.
- [ ] `KRuntime.readFileAsync(Object)` returns `KTask.completed(content)` instead of raw `String`.
- [ ] JVM codegen emits an `INVOKEVIRTUAL`/`INVOKESTATIC` call for `await` expressions instead of being a no-op.
- [ ] `KTask.get()` for a completed task returns the value immediately (no blocking, no virtual threads).
- [ ] `KTask.get()` for an incomplete task throws a TODO error: `"TODO: virtual thread suspension (S01-02)"`.
- [ ] Existing tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.
- [ ] `tests/conformance/runtime/valid/async_await.ks` still passes.
- [ ] `stdlib/kestrel/fs.test.ks` still passes.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/06-typesystem.md` (`Task<T>` built-in type)

## Risks / Notes

- **KTask layout**: Using `CompletableFuture<Object>` is forward-compatible with Loom since virtual threads integrate naturally with `CompletableFuture.get()` (the JVM will unmount the virtual thread when blocked on `get()`).
- **Java version requirement**: Project Loom virtual threads require Java 21+. This story does not use virtual threads yet, but the `CompletableFuture` choice is made with Loom in mind.
- **No new Kestrel syntax or types**: This is purely a runtime/codegen internal change; the surface language is unchanged.
