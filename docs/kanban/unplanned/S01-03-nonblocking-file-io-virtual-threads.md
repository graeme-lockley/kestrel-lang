# Non-blocking File I/O via Virtual Threads

## Sequence: S01-03
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-04, S01-05, S01-06, S01-07, S01-08, S01-09

## Summary

Convert `readFileAsync` to run on a virtual thread, returning a `KTask` that completes when the I/O finishes. Callers that `await` this task block their own virtual thread cheaply while the I/O proceeds. This story establishes the pattern for virtual-thread I/O dispatch that S01-07 (`listDir`), S01-08 (`writeText`), and S01-09 (`runProcess`) replicate for their respective primitives. Error handling is provisional (raw exceptions) — typed `Result<T, E>` error surfaces are deferred to S01-04.

## Current State

After S01-02:
- Virtual thread executor exists. Async function bodies dispatch to virtual threads.
- `readFileAsync` still runs synchronously on the calling thread and returns `KTask.completed(payload)`.
- On I/O error, `readFileAsync` returns empty string `""` — no structured error surface.

## Relationship to other stories

- **Depends on S01-01 and S01-02**: KTask class and virtual thread executor must exist.
- **Enables S01-04**: Once I/O returns a KTask, S01-04 wraps the payload in `Result<String, FsError>`.
- **Enables S01-07, S01-08, S01-09**: Those stories replicate this pattern for `listDir`, `writeText`, and `runProcess` respectively.
- **Audit scope**: This story covers **only `readFileAsync`**. Other I/O primitives have dedicated stories (S01-07, S01-08, S01-09).

## Goals

1. **readFileAsync on virtual thread**: The primitive dispatches file reading to a virtual thread and returns an immediately-available `KTask` backed by a `CompletableFuture` that completes when the read finishes.
2. **Establish the pattern**: This conversion serves as the template for S01-07 (`listDir`), S01-08 (`writeText`), and S01-09 (`runProcess`).
3. **Genuine concurrency for I/O**: Two `readFileAsync` calls can overlap — one does not block the other.
4. **Provisional error handling**: I/O errors are caught and surfaced as exceptions from `KTask.get()` (stub: TODO marker notes that S01-04 will introduce `Result<T, FsError>`).
5. **No caller changes**: Existing Kestrel code using `await Fs.readText(path)` works unchanged; the difference is that the I/O is non-blocking under the hood.

## Acceptance Criteria

- [ ] `KRuntime.readFileAsync(path)` submits the file read to the virtual thread executor and returns a `KTask`.
- [ ] `await Fs.readText("valid-path")` returns the file contents.
- [ ] `await Fs.readText("missing-path")` surfaces an error (exception from `get()`) — not an empty string.
- [ ] Two concurrent `readText` calls overlap on the JVM (verify with test reading two files).
- [ ] `listDir`, `writeText`, and `runProcess` remain synchronous in this story (converted in S01-07, S01-08, S01-09).
- [ ] Stub: error returns are raw exceptions; a TODO comment references S01-04 for `Result<T, FsError>` migration.
- [ ] Existing tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.
- [ ] `stdlib/kestrel/fs.test.ks` updated if needed for error behavior changes (empty string → exception).

## Spec References

- `docs/specs/02-stdlib.md` (filesystem API, `readText`)
- `docs/specs/01-language.md` §5 (Async and Task model)

## Risks / Notes

- **Breaking change: error behavior**: Today `readFileAsync` returns `""` on error. Changing to throw means callers that relied on the empty-string sentinel break. This is intentional — S01-04 introduces the proper `Result` type. During this story, tests must be updated for the new error behavior.
- **Blocking I/O inside virtual threads is fine**: With Project Loom, standard blocking `Files.readAllBytes()` inside a virtual thread is efficient — the JVM unmounts the virtual thread during the OS-level blocking call. No need for NIO or async channels.
- **listDir / writeText / runProcess**: These have dedicated stories (S01-07, S01-08, S01-09) and are not converted in this story.
