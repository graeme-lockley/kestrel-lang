# Virtual Thread Executor and Async Function Launch

## Sequence: S01-02
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-03, S01-04, S01-05, S01-06

## Summary

Add a virtual thread executor (Java 21+ Project Loom) to the JVM runtime. When an `async fun` is called, its body is dispatched to a virtual thread and the caller receives a `KTask` backed by a real `CompletableFuture`. `KTask.get()` (i.e. `await`) blocks the calling virtual thread cheaply — the JVM scheduler unmounts it and resumes it when the future completes. This is the story that turns Kestrel async from "always-synchronous" into genuine concurrent execution.

## Current State

After S01-01:
- `KTask` class exists, wrapping `CompletableFuture<Object>`.
- `completedTask()` returns `KTask.completed(value)`.
- `await` codegen invokes `KTask.get()`.
- All tasks are still created via `completed()` — no virtual threads, no real concurrency.

## Relationship to other stories

- **Depends on S01-01**: KTask class and codegen wiring must be in place.
- **Enables S01-03**: Once the executor exists, I/O primitives can launch work on virtual threads.
- **Enables S01-05**: CLI exit flags depend on executor lifecycle management.
- **Independent of S01-04**: Result/ADT error types are orthogonal to the executor.

## Goals

1. **Virtual thread executor**: Create an executor via `Executors.newVirtualThreadPerTaskExecutor()` (Project Loom) managed by `KRuntime` or a new `KExecutor` class.
2. **Async function dispatch**: When an `async fun` is invoked, its body runs on a virtual thread. The call site immediately receives a `KTask` whose `CompletableFuture` completes when the body finishes.
3. **Cheap await blocking**: `KTask.get()` calls `CompletableFuture.get()` — on a virtual thread this unmounts the carrier thread rather than blocking it.
4. **Concurrency correctness**: Two independent async calls can genuinely overlap; virtual threads are scheduled by the JVM.
5. **Exception propagation**: If an async function body throws, the `CompletableFuture` completes exceptionally; `KTask.get()` re-throws so `await` surfaces the error.
6. **AWAIT inside try/catch**: Because `KTask.get()` throws normally, try/catch around `await` works without special unwind logic — verify with tests.

## Acceptance Criteria

- [ ] A virtual thread executor is created at runtime startup and accessible from `KRuntime`.
- [ ] Calling an `async fun` dispatches its body to a virtual thread and returns a `KTask`.
- [ ] JVM codegen emits the dispatch call for async function invocation (wrapping the body in a `Runnable`/`Callable` submitted to the executor).
- [ ] `await` on a pending KTask blocks the calling virtual thread until the task completes, then returns the value.
- [ ] Two concurrent `await` calls on independent tasks overlap execution (test with a delay or I/O).
- [ ] Exception thrown in async body is caught via `await` in a try/catch block.
- [ ] The `KTask.get()` TODO error from S01-01 is removed — real suspension now works.
- [ ] Stub: async I/O primitives (e.g. `readFileAsync`) still complete synchronously (TODO → S01-03).
- [ ] Existing tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model — suspension semantics)
- `docs/specs/06-typesystem.md` (`Task<T>`)

## Risks / Notes

- **Java 21+ requirement**: Virtual threads (`Executors.newVirtualThreadPerTaskExecutor()`) require Java 21+. Document this in build requirements.
- **Codegen complexity**: Dispatching async function bodies to virtual threads requires wrapping the body in a `Callable` and submitting it. This changes how async functions are compiled — the body becomes a lambda/inner class on the JVM.
- **Thread safety**: Kestrel values are immutable (except mutable vars with `var`). Virtual threads share heap but Kestrel's single-writer semantics should prevent data races. Verify with concurrent tests.
- **Executor shutdown**: The executor must be shut down cleanly when the program exits. S01-05 handles the CLI flags; for now, the executor should shut down when `main` returns (or use `awaitTermination`).
- **No Task.race / Task.all yet**: Combinators for multiple tasks are out of scope; individual `await` is sufficient for this story.
