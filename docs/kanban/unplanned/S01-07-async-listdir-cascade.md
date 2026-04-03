# Async listDir — Signature, Callers, and Cascade

## Sequence: S01-07
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-06, S01-08, S01-09

## Summary

Change `Fs.listDir` from a synchronous `(String) -> List<String>` to an async `(String) -> Task<List<String>>`. This touches the stdlib definition, the `__list_dir` type-checker binding, the JVM codegen intrinsic, the `KRuntime.listDir()` Java implementation, and every Kestrel call site that invokes `Fs.listDir` or the bare `listDir` import. After this story, callers must `await` the result inside an `async` context.

## Current State

- **stdlib/kestrel/fs.ks** — `export fun listDir(path: String): List<String> = __list_dir(path)` (synchronous).
- **compiler/src/typecheck/check.ts** — `__list_dir` typed as `(String) -> List<String>`.
- **compiler/src/jvm-codegen/codegen.ts** — Emits `INVOKESTATIC KRuntime.listDir(Object)KList`.
- **runtime/jvm/src/.../KRuntime.java** — `listDir()` runs blocking I/O on the calling thread, returns `KList` directly; returns `KNil.INSTANCE` on error.
- **Callers (5 call sites)**:
  - `stdlib/kestrel/fs.test.ks:35,42` — test assertions on directory listings.
  - `scripts/run_tests.ks:26,95,96` — test runner enumerates unit and stdlib test directories.

## Relationship to other stories

- **Depends on S01-01 and S01-02**: KTask class and virtual-thread executor must exist so the runtime can return a `KTask`.
- **Depends on S01-03 (partially)**: S01-03 establishes the pattern for converting `readFileAsync` to virtual threads; this story replicates that pattern for `listDir`.
- **Interacts with S01-04**: When S01-04 introduces `Result + FsError`, the `listDir` return type will further change to `Task<Result<List<String>, FsError>>`. This story uses provisional error handling (exceptions via `KTask.get()`).
- **Parallel with S01-08 and S01-09**: All three API-migration stories are independent and can be implemented in any order.

## Goals

1. **Stdlib signature**: `export async fun listDir(path: String): Task<List<String>> = __list_dir_async(path)` (or rename the intrinsic).
2. **Type-checker binding**: `__list_dir` (or new `__list_dir_async`) returns `Task<List<String>>`.
3. **JVM codegen**: Emit `INVOKESTATIC KRuntime.listDirAsync(Object)Object` returning a `KTask`.
4. **KRuntime.java**: `listDirAsync()` submits the directory listing to the virtual-thread executor and returns a `KTask` backed by `CompletableFuture`.
5. **Caller cascade — fs.test.ks**: Convert test functions that call `listDir` to `async`, wrap calls with `await`.
6. **Caller cascade — run_tests.ks**: The test-runner script (`scripts/run_tests.ks`) calls `listDir` in three places. Convert the relevant functions to `async` and add `await` at each call site. If the entry point (`main` or top-level) is not already async, make it async.
7. **Provisional errors**: On I/O failure, the KTask completes exceptionally; callers that `await` see an exception. Stub: TODO referencing S01-04 for `Result<List<String>, FsError>`.

## Acceptance Criteria

- [ ] `Fs.listDir("valid-dir")` returns `Task<List<String>>`; callers use `await`.
- [ ] `stdlib/kestrel/fs.ks` signature updated.
- [ ] `__list_dir` type binding in `compiler/src/typecheck/check.ts` returns `Task<List<String>>`.
- [ ] JVM codegen emits the async variant and wraps the return in `KTask`.
- [ ] `KRuntime.java` `listDirAsync()` dispatches to the virtual-thread executor.
- [ ] `stdlib/kestrel/fs.test.ks` updated: test functions are `async`, calls use `await`.
- [ ] `scripts/run_tests.ks` updated: all `listDir` call sites use `await`, enclosing functions are `async`.
- [ ] `docs/specs/02-stdlib.md` `listDir` entry updated to reflect `Task<List<String>>` signature.
- [ ] Error on missing directory: `KTask.get()` throws (not silent `KNil`); tests assert the error case.
- [ ] All test suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/02-stdlib.md` (`kestrel:fs` — `listDir` signature)
- `docs/specs/01-language.md` §5 (Async and Task model)

## Risks / Notes

- **run_tests.ks is the Kestrel test runner**: Making it async may require `scripts/kestrel test` to handle an async entry point. Verify the CLI runner supports async `main` or top-level `await`.
- **Error behavior change**: Today `listDir` returns `KNil.INSTANCE` (empty list) on error. After this story, errors throw from `await`. Callers that relied on empty-list-on-error must be updated.
- **S01-04 will further change the type**: After S01-04, `listDir` becomes `Task<Result<List<String>, FsError>>`. This story's callers will need another update unless S01-04 is implemented first. Accept the double-touch as the cost of incremental delivery.
