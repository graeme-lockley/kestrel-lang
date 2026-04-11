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

## Risks / Notes

- `mtimeMs` is a 64-bit epoch millisecond value — fits in Kestrel `Int` (also 64-bit).
- `size` in bytes — also `Int`.
- `createDirectories` is idempotent on existing dirs; no special-case needed.
- Depends on nothing else in E13; independent of S13-01.
- S13-11 (recursive listDir) depends on this story (for the `isDir` check).
