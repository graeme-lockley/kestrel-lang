# Recursive `listDir` and `collectFiles`

## Sequence: S13-11
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add `listDirAll` (recursive directory listing) and `collectFilesByExtension` to `kestrel:io/fs`. The compiler's `--clean` flag walks the incremental cache directory recursively to find and delete all `.kti` files; this requires a recursive listing operation.

## Current State

`io/fs.ks` has `listDir` (non-recursive, one level only) and `collectFiles` (internal recursive helper used by the test runner — but it is not exported). KRuntime.java uses `java.nio.file.Files.list()` for the current `listDirAsync`. Adding recursive walk uses `Files.walk()`.

## Goals

1. Export `listDirAll(path: String): Task<Result<List<DirEntry>, FsError>>` — recursively lists all files and directories under `path`, returning `DirEntry` values (`File(path)` or `Dir(path)`). Does not include the root itself.
2. Export `collectFilesByExtension(path: String, ext: String): Task<Result<List<String>, FsError>>` — returns absolute paths of all files under `path` whose name ends with `ext` (e.g. `".kti"`).

## Acceptance Criteria

- `listDirAll(dir)` returns all nested file and directory entries recursively.
- `collectFilesByExtension(dir, ".kti")` returns only `.kti` files (not folders, not files with other extensions).
- Both return `Err(NotFound)` if `path` does not exist.
- Empty directory returns `Ok([])`.

## Spec References

- `docs/specs/02-stdlib.md` (io/fs section)

## Risks / Notes

- **Depends on S13-02** for the `isDir` field on `DirEntry` used to distinguish file vs directory entries during walk.
- Actually, S13-02 adds `stat`; `listDirAll` can use `Files.walk()` in Java directly and encode dir vs file in the entries — no dependency on S13-02 needed. `Files.walk` returns `Stream<Path>` with attributes. Revise: independent of S13-02 except for consistency.
- `Files.walk` follows symlinks by default on some JVMs; use `FileVisitOption` set carefully. Default (no follow) is safer.
