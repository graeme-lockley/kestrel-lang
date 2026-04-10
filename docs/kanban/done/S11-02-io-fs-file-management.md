# kestrel:io/fs file management: fileExists, deleteFile, renameFile

## Sequence: S11-02
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E11 Pure-Kestrel Test Runner](../epics/unplanned/E11-pure-kestrel-test-runner.md)

## Summary

Add three file-management operations to `kestrel:io/fs`: `fileExists`, `deleteFile`, and `renameFile`. These fill gaps needed by the updated `test-runner.ks` — specifically `renameFile` replaces the `sh -c "cmp -s … && rm … || mv …"` subprocess trick used for atomic file replacement, and `fileExists`/`deleteFile` are natural companions.

## Current State

`stdlib/kestrel/io/fs.ks` provides `readText`, `listDir`, `writeText`, `readStdin`, `pathBaseName`, and `collectFiles`. `KRuntime.java` has no `fileExists`, `deleteFile`, or `renameFile` methods.

## Relationship to other stories

- Required by **S11-03** (test-runner uses `renameFile` for atomic temp→dest swap).
- No dependency on S11-01.

## Goals

1. `fileExists(path: String): Task<Bool>` — returns `True` if path exists as a file or directory.
2. `deleteFile(path: String): Task<Result<Unit, FsError>>` — deletes the file; succeeds silently if not found.
3. `renameFile(src: String, dest: String): Task<Result<Unit, FsError>>` — atomically moves src to dest (using `StandardCopyOption.REPLACE_EXISTING`).

## Acceptance Criteria

- `fileExists` returns `True` for an existing file and `False` for a missing path.
- `deleteFile` deletes a file and returns `Ok(())`.
- `renameFile` moves a file and the source no longer exists.
- All three are exported from `kestrel:io/fs`.
- Conformance runtime tests exercise each function.

## Spec References

- `docs/specs/02-stdlib.md` (io/fs section)

## Risks / Notes

- `renameFile` uses `Files.move(src, dest, REPLACE_EXISTING)` which is atomic on most POSIX systems (same filesystem). Cross-device moves fall back to copy+delete on JVM; document this.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | Add `fileExistsAsync`, `deleteFileAsync`, `renameFileAsync` to `KRuntime.java` |
| Stdlib | Add `fileExists`, `deleteFile`, `renameFile` to `stdlib/kestrel/io/fs.ks` and export them |
| Tests | New conformance runtime test `tests/conformance/runtime/valid/fs_file_ops.ks` |
| Docs | Add three functions to `docs/specs/02-stdlib.md` io/fs section |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `fileExistsAsync(Object)`, `deleteFileAsync(Object)`, `renameFileAsync(Object, Object)`
- [x] `stdlib/kestrel/io/fs.ks`: add extern funs + wrappers for `fileExists`, `deleteFile`, `renameFile`; export all three
- [x] `tests/conformance/runtime/valid/fs_file_ops.ks`: test all three operations
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/fs_file_ops.ks` | `fileExists` true/false; `deleteFile` removes a file; `renameFile` moves a file |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `fileExists`, `deleteFile`, `renameFile` to the io/fs section

## Build notes

- 2026-04-10: Started implementation.
- 2026-04-10: Used `StandardCopyOption.REPLACE_EXISTING` for renameFile (no `ATOMIC_MOVE` since it throws on cross-device moves). `deleteFileAsync` uses `Files.deleteIfExists` so missing-file is not an error. `fileExistsAsync` is synchronous-semantically but wrapped in the async executor for consistency with other io/fs ops.
