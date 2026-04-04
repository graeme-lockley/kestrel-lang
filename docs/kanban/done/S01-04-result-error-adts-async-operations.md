# Result and Error ADTs for Async Operations

## Sequence: S01-04
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/done/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-05, S01-06, S01-07, S01-08, S01-09

## Summary

Introduce typed error handling for async I/O operations. All async primitives that can fail (`readText`, `listDir`, `writeText`, `runProcess`) return `Task<Result<T, E>>` where `E` is an enumerated error ADT specific to the domain (e.g. `FsError` for file operations, `ProcessError` for process operations). This replaces the provisional exception-based error surface from S01-03/07/08/09 with a type-safe, pattern-matchable error model. The compiler typing, stdlib signatures, and runtime error returns are all updated.

## Current State

After S01-03:
- `readFileAsync` runs on a virtual thread and returns a `KTask`.
- On I/O error, `KTask.get()` throws a Java exception — callers must catch or crash.
- No `Result` type in the async error path (stdlib has `Result` in `stdlib/kestrel/result.ks` for general use).
- Stdlib type signature: `readText(path: String): Task<String>`.

## Relationship to other stories

- **Depends on S01-03**: I/O primitives must return KTask before wrapping in Result.
- **Depends on S01-01 and S01-02**: Runtime and executor must be in place.
- **Independent of S01-05**: CLI flags are orthogonal.
- **Enables S01-06**: Conformance tests validate the Result-typed async surface.
- **Informs Epic E03**: HTTP and networking stories will follow the same `Task<Result<T, E>>` pattern established here.

## Goals

1. **FsError ADT**: Define an error ADT for file-system operations (e.g. `NotFound`, `PermissionDenied`, `IoError(message: String)`) in `stdlib/kestrel/fs.ks` or a companion module.
2. **readText returns Result**: Update `readText` signature to `Task<Result<String, FsError>>`. The runtime catches I/O exceptions and wraps them as `Result.Err(FsError.*)`.
3. **Pattern-matchable errors**: Callers can `match` on the `Result` to handle specific failure modes.
4. **Compiler typing updated**: `__read_file_async` primitive type in the type checker reflects the new `Task<Result<String, FsError>>` signature.
5. **Other I/O primitives**: Any other async primitives audited in S01-03 (writeText, listDir, etc.) get analogous error ADTs if they have meaningful failure modes.
6. **No ad-hoc sentinels**: Remove empty-string error returns and exception-based error paths from the async I/O surface.

## Acceptance Criteria

- [x] `FsError` ADT is defined (at minimum: `NotFound`, `PermissionDenied`, `IoError`) and exported from `stdlib/kestrel/fs.ks`.
- [x] `Fs.readText(path)` has type `Task<Result<String, FsError>>`.
- [x] `await Fs.readText("valid-path")` returns `Ok(contents)`.
- [x] `await Fs.readText("missing-path")` returns `Err(FsError.NotFound)` (or similar).
- [x] Compiler type checker updated: `__read_file_async` returns `Task<Result<String, FsError>>`.
- [x] `stdlib/kestrel/fs.test.ks` updated with tests for Ok and Err paths using pattern matching.
- [x] Other implemented async I/O primitives have analogous Result-wrapped return types.
- [x] No async I/O primitive returns a raw payload or throws on expected errors — all use Result.
- [x] Existing tests updated and passing: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/02-stdlib.md` (filesystem API, error types)
- `docs/specs/06-typesystem.md` (`Result`, ADTs, `Task`)
- `docs/specs/01-language.md` §5 (Task model)

## Risks / Notes

- **Breaking surface change**: Moving `readText` from `Task<String>` to `Task<Result<String, FsError>>` breaks all existing callers. All call sites in tests, stdlib, and E2E must be updated. This is the intentional migration.
- **Result type availability**: `stdlib/kestrel/result.ks` already defines `Result<A, E>` with `Ok(value)` and `Err(error)` constructors. Verify it is compatible with the needed usage pattern (pattern matching, type inference).
- **Error ADT granularity**: Keep `FsError` simple for now (3–4 constructors). Finer-grained errors can be added later without breaking the ADT match exhaustiveness if we include a catch-all like `IoError(message: String)`.
- **JVM mapping**: Java `IOException` subclasses map to `FsError` constructors: `NoSuchFileException` → `NotFound`, `AccessDeniedException` → `PermissionDenied`, others → `IoError(e.getMessage())`.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler typecheck (`compiler/src/typecheck/check.ts`) | Update primitive intrinsic types from provisional async/sync signatures to `Task<Result<...>>` forms for `__read_file_async`, and for audited async primitives (`__list_dir*`, `__write_text*`, `__run_process*`) so inference and `await` unwrapping remain sound. Compatibility risk: high at compile time (intentional break), rollback is straightforward by restoring old primitive signatures. |
| JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | Repoint intrinsic call lowering to Result-returning async runtime entry points and keep stack behavior consistent for `Task` values. Risk: mismatched descriptors can fail at runtime linkage; mitigate with targeted integration tests. |
| JVM runtime (`runtime/jvm/src/kestrel/runtime/KRuntime.java`) | Replace exception/sentinel behavior with explicit Result payload construction inside async tasks. Add Java exception-to-ADT mapping (`NoSuchFileException`, `AccessDeniedException`, generic IO) and ensure all expected operational failures complete with `Err(...)` instead of exceptional completion. Compatibility risk: behavior change for callers that currently rely on catch-all exception flow. |
| Stdlib surface (`stdlib/kestrel/fs.ks`, `stdlib/kestrel/process.ks`) | Introduce exported error ADTs (`FsError`, plus process/list/write variants as needed) and migrate signatures to `Task<Result<T, E>>`. This is the intentional breaking change called out in Risks/Notes; all call sites must pattern match on `Ok/Err`. |
| Scripts and harness (`scripts/run_tests.ks`, `tests/perf/float/run.ks`) | Cascade caller updates from direct values to `await` + Result pattern matching so test and perf runners continue to function after the signature migration. Risk: broad call-site churn; mitigate by updating helper utilities first. |
| Tests (compiler, stdlib, conformance, e2e) | Replace exception-path assertions with `Err(...)` assertions and add regression tests for constructor-specific error mapping. Include cross-module and async overlap checks to guard against accidental reversion to exceptional completion or sentinel values. |
| Specs (`docs/specs/02-stdlib.md`, `docs/specs/06-typesystem.md`, `docs/specs/01-language.md`) | Update normative contracts from provisional exception text to typed `Task<Result<T, E>>` semantics and document that operational failures are data (`Err`) rather than thrown exceptions on await. |

## Tasks

- [x] Typecheck intrinsics in `compiler/src/typecheck/check.ts`: change `__read_file_async` to `Task<Result<String, FsError>>`, and migrate audited async I/O/process intrinsics (`listDir`, `writeText`, `runProcess`) to `Task<Result<...>>` signatures with concrete ADT error types.
- [x] JVM intrinsic lowering in `compiler/src/jvm-codegen/codegen.ts`: update intrinsic name/descriptor mappings to call Result-returning async runtime methods for read/list/write/process.
- [x] JVM runtime implementation in `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add async Result-returning methods, map Java IO/process failures to ADT constructors, and remove expected-error sentinel/exception behavior from async I/O surface.
- [x] Stdlib API in `stdlib/kestrel/fs.ks`: add/export `FsError` ADT, migrate `readText`, `listDir`, and `writeText` signatures to `Task<Result<...>>`, and expose helper constructors/types needed by callers.
- [x] Stdlib API in `stdlib/kestrel/process.ks`: add/export `ProcessError` (or equivalent) and migrate `runProcess` to `Task<Result<Int, ProcessError>>`.
- [x] Cascade call sites in `scripts/run_tests.ks`: make filesystem/process usage async and pattern match `Ok/Err` so test discovery and runner generation preserve current UX and exit behavior.
- [x] Cascade call sites in `tests/perf/float/run.ks` and other runtime callers using `Process.runProcess`/`Fs.*`: convert to async + Result handling without changing benchmark accounting semantics.
- [x] Update stdlib regression coverage in `stdlib/kestrel/fs.test.ks`: assert `Ok` for happy paths and constructor-specific `Err` values for missing file, denied access, and generic IO mapping cases.
- [x] Update compiler integration coverage in `compiler/test/integration/runtime-stdlib.test.ts` (and related async runtime tests): assert Result payload semantics instead of exception propagation.
- [x] Add conformance and e2e regression cases for `Task<Result<...>>` async fs/process behavior and pattern matching across module boundaries.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Replace catch-based missing-path assertion with `await` + Result match, and add checks that `readText` success returns `Ok(contents)` while missing path returns `Err(FsError.NotFound)`.
| Vitest integration | `compiler/test/integration/jvm-async-runtime.test.ts` | Verify async runtime now completes with Result payloads for operational fs/process failures rather than exceptional task completion.
| Kestrel harness | `stdlib/kestrel/fs.test.ks` | Add explicit pattern-match tests for `Ok`, `Err(FsError.NotFound)`, `Err(FsError.PermissionDenied)`, and generic `Err(FsError.IoError(_))` mapping.
| Kestrel harness | `stdlib/kestrel/process.test.ks` | Add async Result tests for successful command exit codes and failure mapping into `ProcessError` constructors.
| Kestrel harness | `tests/unit/async_virtual_threads.test.ks` | Extend async tests to ensure `await` on fs/process tasks yields `Result` values and preserves virtual-thread overlap behavior.
| Conformance runtime | `tests/conformance/runtime/valid/async_read_text_overlap.ks` | Update expected program shape to pattern match on `Ok` values while preserving overlap timing signal.
| E2E positive | `tests/e2e/scenarios/positive/async-readtext-result-errors.ks` | End-to-end program validates `Ok` on existing file and constructor-specific `Err` on missing file via printed outputs.
| E2E negative | `tests/e2e/scenarios/negative/async-fs-result-type-mismatch.ks` | Ensure type checker rejects stale pre-migration usage that treats `await Fs.readText(...)` as `String` instead of `Result<String, FsError>`.

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — update `kestrel:fs` and `kestrel:process` signatures and behavior text from provisional exception/sentinel handling to typed `Task<Result<T, E>>` ADT contracts.
- [x] `docs/specs/06-typesystem.md` — add/clarify async primitive examples so `await` over fs/process now unwraps to `Result<..., ...>` values and preserve ADT typing expectations.
- [x] `docs/specs/01-language.md` — revise async runtime note to remove provisional exceptional-readText wording and describe failure-as-data behavior for these stdlib async operations.

## Build notes

- 2026-04-03: Started implementation from planned scope and moved story to doing.
- 2026-04-03: Implemented Result-returning async runtime primitives for read/list/write/process and switched JVM codegen/typecheck intrinsics to Task<Result<...>>.
- 2026-04-03: Exported `FsError` / `ProcessError` ADTs in stdlib modules and mapped runtime error strings to typed constructors in stdlib to keep external API pattern-matchable.
- 2026-04-03: Updated scripts, perf harness, stdlib tests, conformance, and e2e scenarios for Result-based async behavior.
- 2026-04-03: Verified with `cd compiler && npm run build && npm test`, `cd runtime/jvm && bash build.sh`, `./scripts/kestrel test`, and `./scripts/run-e2e.sh` (all passing).
