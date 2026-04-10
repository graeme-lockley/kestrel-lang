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
