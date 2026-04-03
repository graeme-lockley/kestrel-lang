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

- [x] `KTask.java` exists in `runtime/jvm/src/kestrel/runtime/` with `completed(Object)` and `get()` methods.
- [x] `KRuntime.completedTask(Object)` returns a `KTask` instance.
- [x] `KRuntime.readFileAsync(Object)` returns `KTask.completed(content)` instead of raw `String`.
- [x] JVM codegen emits an `INVOKEVIRTUAL`/`INVOKESTATIC` call for `await` expressions instead of being a no-op.
- [x] `KTask.get()` for a completed task returns the value immediately (no blocking, no virtual threads).
- [x] `KTask.get()` for an incomplete task throws a TODO error: `"TODO: virtual thread suspension (S01-02)"`.
- [x] Existing tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.
- [x] `tests/conformance/runtime/valid/async_await.ks` still passes.
- [x] `stdlib/kestrel/fs.test.ks` still passes.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/06-typesystem.md` (`Task<T>` built-in type)

## Risks / Notes

- **KTask layout**: Using `CompletableFuture<Object>` is forward-compatible with Loom since virtual threads integrate naturally with `CompletableFuture.get()` (the JVM will unmount the virtual thread when blocked on `get()`).
- **Java version requirement**: Project Loom virtual threads require Java 21+. This story does not use virtual threads yet, but the `CompletableFuture` choice is made with Loom in mind.
- **No new Kestrel syntax or types**: This is purely a runtime/codegen internal change; the surface language is unchanged.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler (parser/typecheck) | No grammar or type rule changes expected in `compiler/src/parser/parse.ts` and `compiler/src/typecheck/check.ts`; verify `AwaitExpr` still enforces async context and `Task<T>` input while runtime representation changes under the hood. |
| Compiler (JVM codegen) | Update `compiler/src/jvm-codegen/codegen.ts` so `AwaitExpr` emits `CHECKCAST kestrel/runtime/KTask` plus `INVOKEVIRTUAL get()Ljava/lang/Object;` instead of passthrough. Update async-return wrapping and `__read_file_async` intrinsic method descriptors to use `Lkestrel/runtime/KTask;` where required. |
| JVM runtime | Add new `runtime/jvm/src/kestrel/runtime/KTask.java` wrapping `CompletableFuture<Object>` with `completed(Object)` and `get()`. Update `runtime/jvm/src/kestrel/runtime/KRuntime.java` to add/restore `completedTask(Object): KTask` and change `readFileAsync(Object): KTask` to return `KTask.completed(content)`. `KTask.get()` must throw `RuntimeException("TODO: virtual thread suspension (S01-02)")` for incomplete tasks. |
| Stdlib | Keep `stdlib/kestrel/fs.ks` API surface unchanged (`readText: Task<String>`). Validate no signature cascade is needed in this story (cascades are deferred to S01-07/S01-08/S01-09). |
| Tests | Add/extend compiler integration and runtime conformance coverage to prove `await` now executes via `KTask.get()` and that completed tasks remain behaviorally identical for users (`async_await`, `fs.test`). Add regression coverage for descriptor/linkage correctness to prevent `NoSuchMethodError` at JVM runtime. |
| Scripts / CLI | No CLI flag or script behavior change in this story; compatibility remains synchronous from user perspective. Rollback risk is low: reverting to passthrough await and raw payload returns restores prior behavior if required. |

## Tasks

- [x] Parser: audit `compiler/src/parser/parse.ts` `await` parsing path (`parsePrimary`) and confirm no AST shape change is required for S01-01.
- [x] Typecheck: audit `compiler/src/typecheck/check.ts` `AwaitExpr` inference to ensure `await` still requires `Task<T>` and returns `T` with no runtime-class coupling.
- [x] Bytecode codegen (non-JVM): verify `compiler/src/codegen/codegen.ts` requires no changes for this JVM-only story; document explicit no-op in build notes when implementing.
- [x] JVM codegen: update `compiler/src/jvm-codegen/codegen.ts` `AwaitExpr` emission to call `kestrel/runtime/KTask.get()` and update all related method descriptors for `completedTask` / `readFileAsync` task-returning intrinsics.
- [x] JVM runtime: add `runtime/jvm/src/kestrel/runtime/KTask.java` implementing `completed(Object)` and `get()` over `CompletableFuture<Object>` with S01-02 TODO behavior for incomplete tasks.
- [x] JVM runtime: update `runtime/jvm/src/kestrel/runtime/KRuntime.java` (`completedTask`, `readFileAsync`) to construct and return `KTask` consistently.
- [x] JVM runtime build plumbing: include `runtime/jvm/src/kestrel/runtime/KTask.java` in `runtime/jvm/build.sh` so the runtime jar contains the new task type.
- [x] Stdlib validation: confirm `stdlib/kestrel/fs.ks` and current async stdlib call sites remain source-compatible without edits in this story.
- [x] Tests: add/update compiler and Kestrel runtime tests listed below to cover await dispatch through `KTask` and preserve current observable behavior.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Add regression that compiles and runs an async snippet using `await`, asserting JVM execution succeeds with new `KTask`-based await plumbing and no linkage errors. |
| Kestrel harness | `stdlib/kestrel/fs.test.ks` | Keep/extend async `readText` coverage to ensure `await Fs.readText(...)` still returns expected payload when runtime now returns `KTask`. |
| Conformance runtime | `tests/conformance/runtime/valid/async_await.ks` | Extend from declaration-only check to assert an awaited completed task path executes and prints expected value, guarding `AwaitExpr -> KTask.get()` wiring. |
| E2E positive | `tests/e2e/scenarios/positive/async-await-ktask-wiring.ks` | New end-to-end scenario validating async function + await behavior remains synchronous/compatible after introducing runtime `KTask` wrapper. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — update async/await runtime wording in section 5 and/or expression semantics to describe that JVM await unwraps `Task<T>` through runtime task object access (`KTask.get` equivalent behavior).
- [x] `docs/specs/06-typesystem.md` — update Task/await implementation note in section 6 to align with concrete JVM `Task<T>` runtime representation (completed vs incomplete task behavior and S01-02 TODO boundary).

## Notes

- Current source appears to have `readFileAsync` and `AwaitExpr` passthrough, and JVM codegen references `KRuntime.completedTask(...)` descriptor paths that should be validated as part of this story to avoid runtime linkage drift.

## Build notes

- 2026-04-03: Started implementation from `planned/`; codebase still matches the planned S01-01 scope (await passthrough + sync `readFileAsync`).
- 2026-04-03: Codebase divergence found during implementation: `KRuntime.completedTask(...)` did not exist yet (rather than returning an ad-hoc wrapper). Added as part of S01-01 and aligned all JVM codegen descriptors to concrete `KTask` return types.
- 2026-04-03: Additional scope emerged: `runtime/jvm/build.sh` compiles a fixed source list, so `KTask.java` had to be added explicitly to avoid javac symbol failures.
- 2026-04-03: Validation complete. Required suites all pass: compiler build/tests, runtime build, Kestrel harness tests, and E2E scenarios (including new `async-await-ktask-wiring`).
