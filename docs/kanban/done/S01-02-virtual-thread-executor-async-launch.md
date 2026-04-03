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

The current workspace has diverged from the original plan: S01-01 is already done, the epic still links S01-02 through `unplanned/`, and the JVM runtime/build still target synchronous task completion with Java 11-era tooling. This story closes that gap directly.

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

- [x] `runtime/jvm/build.sh` updated from `-source 11 -target 11` to `--release 21` (Project Loom requires Java 21+).
- [x] `README.md` and `CONTRIBUTING.md` updated to require Java 21+ (currently state "Java 11+").
- [x] A virtual thread executor is created at runtime startup and accessible from `KRuntime`.
- [x] Calling an `async fun` dispatches its body to a virtual thread and returns a `KTask`.
- [x] JVM codegen emits the dispatch call for async function invocation (wrapping the body in a `Runnable`/`Callable` submitted to the executor).
- [x] `await` on a pending KTask blocks the calling virtual thread until the task completes, then returns the value.
- [x] Two concurrent `await` calls on independent tasks overlap execution (test with a delay or I/O).
- [x] Exception thrown in async body is caught via `await` in a try/catch block.
- [x] The `KTask.get()` TODO error from S01-01 is removed — real suspension now works.
- [x] Stub: async I/O primitives (e.g. `readFileAsync`) still complete synchronously (TODO → S01-03).
- [x] Existing tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model — suspension semantics)
- `docs/specs/06-typesystem.md` (`Task<T>`)

## Risks / Notes

- **Java 21+ requirement**: Virtual threads (`Executors.newVirtualThreadPerTaskExecutor()`) require Java 21+. Document this in build requirements.
- **Codegen complexity**: Dispatching async function bodies to virtual threads requires wrapping the body in a `Callable` and submitting it. This changes how async functions are compiled — the body becomes a lambda/inner class on the JVM.
- **Thread safety**: Kestrel values are immutable (except mutable vars with `var`). Virtual threads share heap but Kestrel's single-writer semantics should prevent data races. Verify with concurrent tests.
- **Executor shutdown**: The executor must be shut down cleanly when the program exits. S01-05 handles the CLI flags; for now, the executor should shut down when `main` returns (or use `awaitTermination`).
- **No Task.race / Task.all yet**: Combinators for multiple tasks are out of scope; individual `await` is sufficient for this story.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler (parser / typecheck) | No grammar changes are expected in `compiler/src/parser/parse.ts`, and no type-rule changes are expected in `compiler/src/typecheck/check.ts`; implementation should verify that `async fun` still requires `Task<T>` and `AwaitExpr` still unwraps `Task<T>` without coupling the type system to Loom-specific runtime classes. |
| Compiler (non-JVM bytecode) | `compiler/src/codegen/codegen.ts` should remain unchanged for this JVM-only story; record the explicit no-op so the async roadmap does not accidentally diverge across backends while the VM path is still present in docs and tests. |
| Compiler (JVM codegen) | Update `compiler/src/jvm-codegen/codegen.ts` so async function emission no longer wraps results with `KRuntime.completedTask(...)` inline. Instead, async call sites must construct or submit a callable/lambda into the runtime executor, `AwaitExpr` must block via `KTask.get()`, and the generated `main` / module startup path must initialize and shut down the executor predictably. This is the main codegen risk area because async bodies already lower through helper methods and lambda classes. |
| JVM runtime | Extend `runtime/jvm/src/kestrel/runtime/KTask.java` from "completed-task wrapper" to "pending or completed future wrapper", and update `runtime/jvm/src/kestrel/runtime/KRuntime.java` (or a new adjacent runtime helper) to own the virtual-thread executor, submit async bodies, unwrap `ExecutionException` causes, and preserve synchronous `completedTask()` for primitives that stay stubbed until S01-03. This is also where the Java 21 requirement and executor-shutdown risk land. |
| Stdlib | Keep `stdlib/kestrel/fs.ks`, `stdlib/kestrel/process.ks`, and current `Task<T>`-typed APIs source-compatible in this story. `readText` remains a synchronous stub that returns an already-completed `KTask`, so no signature cascade should happen here; that rollback boundary keeps S01-02 focused on async function launch only. |
| Tests | Extend JVM-facing coverage across `compiler/test/integration/runtime-conformance.test.ts`, `tests/conformance/runtime/valid/async_await.ks`, `stdlib/kestrel/fs.test.ks`, and a dedicated Kestrel async regression test so the story proves three things: pending-task await works, independent async launches overlap, and exceptions thrown in async bodies propagate through `await` into `try/catch`. Deterministic overlap coverage may require a narrow JVM-only helper or a portable external-process delay rather than a CPU busy loop. |
| Scripts / build / docs | Update `runtime/jvm/build.sh` to `--release 21`, and update `README.md` / `CONTRIBUTING.md` to make Java 21+ a hard prerequisite for the JVM backend. Existing compiler-emitted class files still target the current classfile version unless implementation discovers a need to raise that separately, so rollback is limited to runtime/tooling changes rather than the full compiler pipeline. |

## Tasks

- [x] Parser: audit `compiler/src/parser/parse.ts` async / await parsing paths (`parseFunDecl`, `parsePrimary`) and confirm no grammar change is required for virtual-thread execution.
- [x] Typecheck: audit `compiler/src/typecheck/check.ts` async-context tracking and `AwaitExpr` inference so `await` continues to require `Task<T>` and unwrap to `T` with no Loom-specific type changes.
- [x] Bytecode codegen (non-JVM): verify `compiler/src/codegen/codegen.ts` needs no changes for this JVM-only story and record that no-op in build notes when implementing.
- [x] JVM codegen: update `compiler/src/jvm-codegen/codegen.ts` `AwaitExpr` emission and async-call lowering so awaited values come from `KTask.get()` on pending tasks rather than passthrough / immediately completed wrappers.
- [x] JVM codegen: update `compiler/src/jvm-codegen/codegen.ts` async function/helper emission and generated `main` startup path so async bodies are submitted through runtime executor hooks and the runtime lifecycle is initialized and shut down cleanly.
- [x] JVM import metadata: thread async-function flags through `compiler/src/compile-file-jvm.ts` so imported and namespace async calls use `KTask`-returning descriptors instead of legacy object-returning signatures.
- [x] JVM runtime: extend `runtime/jvm/src/kestrel/runtime/KTask.java` with pending-task construction, blocking `get()`, and exceptional completion unwrapping for `await`.
- [x] JVM runtime: update `runtime/jvm/src/kestrel/runtime/KRuntime.java` (or add a focused neighboring runtime helper) to create the virtual-thread executor at startup, expose a submission helper for async functions, preserve `completedTask()` for still-synchronous primitives, and shut the executor down on process exit.
- [x] JVM runtime build: update `runtime/jvm/build.sh` to compile the runtime with Java 21 (`--release 21`) and include any new runtime source files.
- [x] Stdlib validation: confirm `stdlib/kestrel/fs.ks`, `stdlib/kestrel/process.ks`, and current async call sites remain source-compatible while `readFileAsync` and other I/O primitives stay synchronous stubs until follow-up stories.
- [x] Docs: update `README.md` and `CONTRIBUTING.md` to require Java 21+ and explain the Project Loom dependency for JVM async execution.
- [x] Tests: add or update the suites listed below to cover executor-backed async launch, overlapping execution, pending-task await, and exception propagation through `await`.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/jvm-async-runtime.test.ts` | Compile and run focused JVM-targeted async snippets that assert an `async fun` returns a task immediately, `await` blocks until completion, and async exceptions surface at the `await` site instead of being swallowed inside the future. |
| Vitest integration | `compiler/test/integration/runtime-conformance.test.ts` | Keep the conformance harness green after extending `tests/conformance/runtime/valid/async_await.ks` from declaration-only coverage to real async execution coverage. |
| Kestrel harness | `tests/unit/async_virtual_threads.test.ks` | Add user-facing regression coverage for parallel async launches, `await` inside `try/catch`, and any deterministic elapsed-time assertion or ordering signal used to prove overlap. |
| Kestrel harness | `stdlib/kestrel/fs.test.ks` | Preserve the existing `await Fs.readText(...)` regression so S01-02 proves the old synchronous stub path still works while async function launch becomes genuinely concurrent. |
| Conformance runtime | `tests/conformance/runtime/valid/async_await.ks` | Extend the runtime conformance file to assert actual awaited execution on the JVM, not just parsing and linkage of an `async fun` declaration. |
| E2E positive | `tests/e2e/scenarios/positive/async-await-virtual-threads.ks` | End-to-end CLI scenario that exercises executor startup, async launch, await completion, and clean shutdown on the real runtime path. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — update §5 runtime semantics so `await` is described in terms of `Task<T>` / `KTask` completion on the JVM rather than the old "suspend frame" wording alone, and document exception propagation through `await`.
- [x] `docs/specs/06-typesystem.md` — update §6 async / await wording so the `Task<T>` discussion matches the concrete JVM runtime model without changing the surface type rules.
- [x] `README.md` — update the prerequisite and quick-start text from JDK 11+ to Java 21+ and mention Project Loom as the reason.
- [x] `CONTRIBUTING.md` — update the prerequisites table and runtime build note to `--release 21`, and clarify that JVM backend work now requires Java 21+.

## Notes

- The most likely deterministic overlap test is a JVM-only integration or E2E program that uses a narrow delay source (for example a portable subprocess sleep) rather than busy-loop timing, which would be too flaky for CI.
- `compiler/src/jvm-codegen/classfile.ts` still emits older classfile versions for generated user classes. Running those classes on Java 21 is fine, but if executor-related lowering requires newer bytecode constructs, raise that as an explicit follow-up rather than silently expanding this story.

## Build notes

- 2026-04-03: Started implementation.
- 2026-04-03: Codebase divergence from the original plan: S01-01 is already done, but S01-02 still points at stale `unplanned/` links in the epic and still assumes pre-S01-01 workspace state. Implementation will update the story and epic as part of closure.
- 2026-04-03: Reused the existing `KFunctionRef` path rather than inventing a second callable representation. Async public methods now submit private payload helpers through `KRuntime.submitAsync(...)`, which keeps function values and direct calls consistent.
- 2026-04-03: Direct-call descriptors needed extra async metadata from `compile-file-jvm.ts` for named and namespace imports; otherwise imported async functions would still link as `(Object...) -> Object` and fail at runtime.
- 2026-04-03: Shutting the executor down immediately after `$init` returned was too eager because still-running async tasks can submit nested async calls. `KRuntime.runMain(...)` now waits for async quiescence before shutdown so nested `await` chains complete reliably.
- 2026-04-03: Deterministic overlap coverage lives in `compiler/test/integration/jvm-async-runtime.test.ts` via a tiny Java harness that submits sleeping `KFunction`s directly to the runtime executor; Kestrel-language tests focus on `await` success and `try/catch` propagation.
- 2026-04-03: Verification complete. Required suites all pass: `cd compiler && npm run build && npm test`, `cd runtime/jvm && bash build.sh`, `./scripts/kestrel test`, and `./scripts/run-e2e.sh`.