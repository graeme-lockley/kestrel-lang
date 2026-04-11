# Atomic file write (`writeTextAtomic`, `writeBytesAtomic`)

## Sequence: S13-14
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add `writeTextAtomic` and `writeBytesAtomic` to `kestrel:io/fs` using write-to-tmp-then-rename. The compiler's URL import cache and KTI incremental cache files must be written atomically — a partial write on crash must not corrupt the cache. The existing `renameFile` is already atomic on POSIX; this story adds the combined write-then-rename primitive.

## Current State

`io/fs.ks` has `writeText` (direct write, not atomic) and `renameFile` (atomic rename). There is no `writeTextAtomic`. Atomicity can be composed in pure Kestrel: write to a temp path, then rename — but this pattern needs a reliable temp-file name. This story adds both the pattern and a helper to generate temp paths.

## Goals

1. Export `writeTextAtomic(path: String, content: String): Task<Result<Unit, FsError>>` — writes to a sibling temp file, then atomically renames it to `path`.
2. Export `writeBytesAtomic(path: String, bytes: ByteArray): Task<Result<Unit, FsError>>` — same for binary content.
3. Export `tempPath(path: String): String` — returns a sibling temporary path (e.g. `path + ".tmp.<random>"`) for use in manual atomic patterns.
4. The temp file is written in the same directory as the target so rename is on the same filesystem (guaranteed atomic on POSIX).

## Acceptance Criteria

- `writeTextAtomic(path, content)` produces a file at `path` with `content`.
- If the write step fails, `path` is not modified (temp file was never renamed).
- `writeBytesAtomic` works identically for binary content.
- `tempPath(path)` returns a path in the same directory as `path`.
- All three are exported from `kestrel:io/fs`.

## Spec References

- `docs/specs/02-stdlib.md` (io/fs section)

## Risks / Notes

- **Depends on S13-01** (ByteArray type needed for `writeBytesAtomic`).
- `renameFile` on different filesystems may not be atomic on all platforms (Windows). Document this limitation.
- The temp path should include a random component to avoid collisions when multiple processes write to the cache simultaneously. Use `KRuntime.nowMs()` + `Thread.currentThread().threadId()` as a cheap unique suffix.

## Tasks

- [x] Add `KRuntime.tempPath(Object path)` using `System.currentTimeMillis()` + `threadId()`
- [x] Rebuild JVM runtime (`bash build.sh`)
- [x] Add `tempPath`, `writeTextAtomic`, `writeBytesAtomic` to `stdlib/kestrel/io/fs.ks`
- [x] Create conformance test `tests/conformance/runtime/valid/atomic_write.ks`
- [x] Compiler tests: 436 pass
- [x] Update `docs/specs/02-stdlib.md`

## Build notes

- 2026-04-11: `tempPath` uses `currentTimeMillis * 1000 + threadId % 1000` for a cheap collision-resistant suffix.
- `writeTextAtomic` and `writeBytesAtomic` composed entirely in pure Kestrel: `writeText`/`writeBytes` + `renameFile`.
- Kestrel `match` syntax inside async blocks must use `match (expr) { pattern => body }` form, not `match expr with | pattern ->`.
- `val _` as discard in async block works in practice (function exits cleanly when last statement is a discarded `deleteFile`).
