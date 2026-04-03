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

## Impact analysis

| Area | Change |
|------|--------|
| Compiler typecheck (`compiler/src/typecheck/check.ts`) | No signature change expected (`__read_file_async: String -> Task<String>` already matches). Validate that no additional typechecker changes are needed so this stays a runtime-only behavioral shift. |
| JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | Keep existing intrinsic lowering (`__read_file_async` -> `KRuntime.readFileAsync`) and `await` -> `KTask.get()` path. Verify descriptor compatibility after runtime change and add regression coverage for missing-path exceptions through await. |
| JVM runtime (`runtime/jvm/src/kestrel/runtime/KRuntime.java`) | Change `readFileAsync` from synchronous `KTask.completed(...)` to virtual-thread-dispatched task completion using existing executor from S01-02, and replace empty-string sentinel behavior with exceptional completion. Add TODO note pointing to S01-04 for `Result<T, E>` migration. Compatibility risk: intentional break for callers relying on `""` sentinel. Rollback: restore sentinel behavior and synchronous completion. |
| JVM task type (`runtime/jvm/src/kestrel/runtime/KTask.java`) | Confirm existing `CompletableFuture`-backed task and `get()` behavior correctly propagate completion exceptions from `readFileAsync` worker tasks; adjust only if runtime dispatch requires a small helper/factory for future-backed tasks. |
| Stdlib (`stdlib/kestrel/fs.ks`, `stdlib/kestrel/fs.test.ks`) | Keep public `readText: (String) -> Task<String>` API unchanged. Update tests that currently assert `""` for missing files to assert thrown behavior from `await`. Leave `listDir` and `writeText` synchronous in this story per scope boundary with S01-07/S01-08. |
| Tests (`compiler/test/integration/runtime-stdlib.test.ts`, `stdlib/kestrel/fs.test.ks`, `tests/e2e/scenarios/positive/*`, `tests/conformance/runtime/valid/*`) | Add/extend tests for success read, missing-file exception propagation, and overlapping concurrent reads. Guard against regressions where runtime accidentally reverts to completed-immediately/sentinel semantics. |
| Scripts / verification (`scripts/kestrel`, `scripts/run-e2e.sh`) | No script behavior changes expected; story requires running full compiler, Kestrel harness, JVM build, and E2E verification because behavior is user-visible and runtime-backed. |

## Tasks

- [ ] Parser audit: confirm no parser grammar changes are required for this story (`await` / async syntax unchanged).
- [ ] Typecheck audit in `compiler/src/typecheck/check.ts`: confirm `__read_file_async` remains `String -> Task<String>` and no additional type rules are needed.
- [ ] Bytecode codegen audit (`compiler/src/codegen/codegen.ts`): confirm no VM-bytecode path changes are needed for this JVM-focused story.
- [ ] JVM codegen verification in `compiler/src/jvm-codegen/codegen.ts`: keep intrinsic mapping for `__read_file_async` and ensure await path (`KTask.get()`) still matches runtime method descriptors after runtime edits.
- [ ] JVM runtime implementation in `runtime/jvm/src/kestrel/runtime/KRuntime.java`: update `readFileAsync(Object path)` to dispatch file read work onto the virtual-thread executor and return a `KTask` backed by that asynchronous completion rather than `KTask.completed(...)`.
- [ ] JVM runtime error path in `runtime/jvm/src/kestrel/runtime/KRuntime.java`: remove empty-string fallback for read errors and propagate failures through task completion exceptions, with a TODO referencing S01-04 typed `Result<T, FsError>` migration.
- [ ] JVM task wiring in `runtime/jvm/src/kestrel/runtime/KTask.java`: add minimal helper support only if needed so runtime can return task instances backed by asynchronous `CompletableFuture` completion.
- [ ] Stdlib behavior validation in `stdlib/kestrel/fs.ks`: keep `readText` surface signature unchanged and ensure no accidental scope creep to `listDir`/`writeText`.
- [ ] Update `stdlib/kestrel/fs.test.ks` for missing-path behavior change (`""` sentinel -> exception from await) and keep existing sync `listDir` / `writeText` expectations.
- [ ] Add/extend integration and scenario coverage for concurrent overlapping reads and missing-path exception propagation.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `cd runtime/jvm && bash build.sh`.
- [ ] Run `./scripts/kestrel test`.
- [ ] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Add/extend runtime stdlib integration to assert `await Fs.readText(valid)` still returns contents and `await Fs.readText(missing)` now fails via propagated task exception instead of empty string fallback. |
| Kestrel harness | `stdlib/kestrel/fs.test.ks` | Replace missing-file expectation from `""` to explicit failure/assertion path that validates exception surfacing through await; keep coverage for successful read/write and unchanged sync listDir behavior. |
| Conformance runtime | `tests/conformance/runtime/valid/async_read_text_overlap.ks` | New runtime conformance case that starts two file reads and demonstrates both complete correctly in one async flow, guarding non-blocking overlap behavior. |
| E2E positive | `tests/e2e/scenarios/positive/async-readtext-error-propagation.ks` | New JVM end-to-end scenario verifying that missing-path `readText` raises an error at await site (no empty-string sentinel) and that process exits with expected failure/signal output contract. |

## Documentation and specs to update

- [ ] `docs/specs/02-stdlib.md` — update `kestrel:fs` `readText` contract from empty-string-on-error semantics to provisional exception propagation in Task completion, with note that S01-04 will migrate to `Result<T, E>`.
- [ ] `docs/specs/01-language.md` — update §5 async/task runtime notes to reflect that `await` on `readText` may now surface task completion exceptions from runtime I/O failures.
