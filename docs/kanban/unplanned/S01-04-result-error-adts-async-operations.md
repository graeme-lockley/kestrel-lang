# Result and Error ADTs for Async Operations

## Sequence: S01-04
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
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
- **Informs Epic E02**: HTTP and networking stories will follow the same `Task<Result<T, E>>` pattern established here.

## Goals

1. **FsError ADT**: Define an error ADT for file-system operations (e.g. `NotFound`, `PermissionDenied`, `IoError(message: String)`) in `stdlib/kestrel/fs.ks` or a companion module.
2. **readText returns Result**: Update `readText` signature to `Task<Result<String, FsError>>`. The runtime catches I/O exceptions and wraps them as `Result.Err(FsError.*)`.
3. **Pattern-matchable errors**: Callers can `match` on the `Result` to handle specific failure modes.
4. **Compiler typing updated**: `__read_file_async` primitive type in the type checker reflects the new `Task<Result<String, FsError>>` signature.
5. **Other I/O primitives**: Any other async primitives audited in S01-03 (writeText, listDir, etc.) get analogous error ADTs if they have meaningful failure modes.
6. **No ad-hoc sentinels**: Remove empty-string error returns and exception-based error paths from the async I/O surface.

## Acceptance Criteria

- [ ] `FsError` ADT is defined (at minimum: `NotFound`, `PermissionDenied`, `IoError`) and exported from `stdlib/kestrel/fs.ks`.
- [ ] `Fs.readText(path)` has type `Task<Result<String, FsError>>`.
- [ ] `await Fs.readText("valid-path")` returns `Ok(contents)`.
- [ ] `await Fs.readText("missing-path")` returns `Err(FsError.NotFound)` (or similar).
- [ ] Compiler type checker updated: `__read_file_async` returns `Task<Result<String, FsError>>`.
- [ ] `stdlib/kestrel/fs.test.ks` updated with tests for Ok and Err paths using pattern matching.
- [ ] Other implemented async I/O primitives have analogous Result-wrapped return types.
- [ ] No async I/O primitive returns a raw payload or throws on expected errors — all use Result.
- [ ] Existing tests updated and passing: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/02-stdlib.md` (filesystem API, error types)
- `docs/specs/06-typesystem.md` (`Result`, ADTs, `Task`)
- `docs/specs/01-language.md` §5 (Task model)

## Risks / Notes

- **Breaking surface change**: Moving `readText` from `Task<String>` to `Task<Result<String, FsError>>` breaks all existing callers. All call sites in tests, stdlib, and E2E must be updated. This is the intentional migration.
- **Result type availability**: `stdlib/kestrel/result.ks` already defines `Result<A, E>` with `Ok(value)` and `Err(error)` constructors. Verify it is compatible with the needed usage pattern (pattern matching, type inference).
- **Error ADT granularity**: Keep `FsError` simple for now (3–4 constructors). Finer-grained errors can be added later without breaking the ADT match exhaustiveness if we include a catch-all like `IoError(message: String)`.
- **JVM mapping**: Java `IOException` subclasses map to `FsError` constructors: `NoSuchFileException` → `NotFound`, `AccessDeniedException` → `PermissionDenied`, others → `IoError(e.getMessage())`.
