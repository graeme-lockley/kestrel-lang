# Async writeText — Signature, Callers, and Cascade

## Sequence: S01-08
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-06, S01-07, S01-09

## Summary

Change `Fs.writeText` from a synchronous `(String, String) -> Unit` to an async `(String, String) -> Task<Unit>`. This touches the stdlib definition, the `__write_text` type-checker binding, the JVM codegen intrinsic, the `KRuntime.writeText()` Java implementation, and every Kestrel call site that invokes `Fs.writeText` or the bare `writeText` import. After this story, callers must `await` the result inside an `async` context.

## Current State

- **stdlib/kestrel/fs.ks** — `export fun writeText(path: String, content: String): Unit = __write_text(path, content)` (synchronous).
- **compiler/src/typecheck/check.ts** — `__write_text` typed as `(String, String) -> Unit`.
- **compiler/src/jvm-codegen/codegen.ts** — Emits `INVOKESTATIC KRuntime.writeText(Object, Object)V` then pushes `KUnit.INSTANCE`.
- **runtime/jvm/src/.../KRuntime.java** — `writeText()` runs blocking I/O on the calling thread, returns void; throws `RuntimeException` on error.
- **Callers (2 call sites)**:
  - `stdlib/kestrel/fs.test.ks:28` — writes a file for roundtrip test.
  - `scripts/run_tests.ks:121` — writes generated test source.

## Relationship to other stories

- **Depends on S01-01 and S01-02**: KTask class and virtual-thread executor.
- **Depends on S01-03 (partially)**: Establishes the virtual-thread I/O pattern.
- **Interacts with S01-04**: When S01-04 introduces `Result + FsError`, the return type will change to `Task<Result<Unit, FsError>>`. This story uses provisional error handling.
- **Parallel with S01-07 and S01-09**: Independent API-migration stories.

## Goals

1. **Stdlib signature**: `export async fun writeText(path: String, content: String): Task<Unit> = __write_text_async(path, content)` (or rename the intrinsic).
2. **Type-checker binding**: `__write_text` (or new `__write_text_async`) returns `Task<Unit>`.
3. **JVM codegen**: Emit `INVOKESTATIC KRuntime.writeTextAsync(Object, Object)Object` returning a `KTask`. Remove the explicit `KUnit.INSTANCE` push — the KTask wraps the unit result.
4. **KRuntime.java**: `writeTextAsync()` submits the file write to the virtual-thread executor and returns a `KTask<Unit>` backed by `CompletableFuture`.
5. **Caller cascade — fs.test.ks**: Convert the test function containing the `writeText` call to `async`, wrap the call with `await`.
6. **Caller cascade — run_tests.ks**: Add `await` at the `writeText` call site; ensure the enclosing function is `async`.
7. **Provisional errors**: On I/O failure, the KTask completes exceptionally. Stub: TODO referencing S01-04 for `Result<Unit, FsError>`.

## Acceptance Criteria

- [ ] `Fs.writeText("path", "content")` returns `Task<Unit>`; callers use `await`.
- [ ] `stdlib/kestrel/fs.ks` signature updated.
- [ ] `__write_text` type binding in `compiler/src/typecheck/check.ts` returns `Task<Unit>`.
- [ ] JVM codegen emits the async variant returning a `KTask`.
- [ ] `KRuntime.java` `writeTextAsync()` dispatches to the virtual-thread executor.
- [ ] `stdlib/kestrel/fs.test.ks` updated: call uses `await`, enclosing test function is `async`.
- [ ] `scripts/run_tests.ks` updated: `writeText` call uses `await`.
- [ ] `docs/specs/02-stdlib.md` `writeText` entry updated to reflect `Task<Unit>` signature.
- [ ] Error on write failure: `KTask.get()` throws; tests verify error path.
- [ ] All test suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/02-stdlib.md` (`kestrel:fs` — `writeText` signature)
- `docs/specs/01-language.md` §5 (Async and Task model)

## Risks / Notes

- **Codegen change for Unit-returning async**: Today the codegen pushes `KUnit.INSTANCE` after the void call. The async version must instead return a `KTask` that resolves to `KUnit.INSTANCE`. Verify the stack discipline is correct.
- **S01-04 will further change the type**: After S01-04, `writeText` becomes `Task<Result<Unit, FsError>>`. Accept the double-touch cost.
- **Low call-site count**: Only 2 Kestrel call sites, making this the smallest of the three API cascades.
