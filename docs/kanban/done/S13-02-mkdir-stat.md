# `mkdirAll` and `stat` / file metadata

## Sequence: S13-02
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add directory creation (`mkdirAll`), file metadata (`stat`), and file-timestamp management (`touchFile`) to `kestrel:io/fs`. The compiler driver needs to recursively create output directories before writing `.class` files, and needs file modification times to implement incremental-compilation cache freshness.

## Current State

`stdlib/kestrel/io/fs.ks` has no `mkdir`/`mkdirAll`. `KRuntime.java` has no corresponding methods. `io/fs` has no `stat`/metadata call. `KRuntime.java` uses `java.nio.file.Files` already (for `readFile`, `writeText`, `renameFile`) so adding `createDirectories`, `readAttributes`, and `setLastModifiedTime` follows the same pattern.

## Goals

1. Export `mkdirAll(path: String): Task<Result<Unit, FsError>>` — creates the directory and all missing parents. No-ops if the directory already exists.
2. Export `stat(path: String): Task<Result<FileStat, FsError>>` — returns a `FileStat` record `{ mtimeMs: Int, size: Int, isDir: Bool, isFile: Bool }`.
3. Export `touchFile(path: String): Task<Result<Unit, FsError>>` — sets the file's last-modified time to now. Creates an empty file if it doesn't exist.

## Acceptance Criteria

- `mkdirAll("a/b/c")` creates `a`, `a/b`, and `a/b/c` in one call.
- `mkdirAll` on an existing directory returns `Ok(())`.
- `stat` on an existing file returns `Ok(FileStat)` with correct `mtimeMs` and `size`.
- `stat` on a missing path returns `Err(NotFound)`.
- `touchFile` on an existing file updates its mtime.
- `touchFile` on a missing path creates an empty file.
- All new functions exported from `kestrel:io/fs`.

## Spec References

- `docs/specs/02-stdlib.md` (io/fs section)

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `mkdirAllAsync`, `statAsync`, `touchFileAsync`
- [x] `stdlib/kestrel/io/fs.ks`: add `FileStat` record type, extern bindings, `mkdirAll`, `stat`, `touchFile` exports
- [x] `tests/conformance/runtime/valid/fs_mkdir_stat.ks`: test mkdirAll idempotency, stat fields, touchFile, stat NotFound
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm test`
- [x] `./scripts/kestrel test`

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `FileStat` type and mkdirAll/stat/touchFile functions to io/fs section

## Build notes

`statAsync` returns a `KRecord` with fields `mtimeMs`, `size`, `isDir`, `isFile`. The `FileStat` record type on the Kestrel side matches this by structural typing. The pattern is validated by the existing `ProcessResult` record return from `runProcessAsync`.

Async pattern in KRuntime uses: `initAsyncRuntime()` + `synchronized (KRuntime.class) { exec = asyncExecutor; }` + `asyncTasksInFlight.incrementAndGet()` (not `incrementAsyncTasksInFlight()` which does not exist).
