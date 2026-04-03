# Async runProcess — Signature, Callers, and Cascade

## Sequence: S01-09
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-06, S01-07, S01-08

## Summary

Change `Process.runProcess` from a synchronous `(String, List<String>) -> Int` to an async `(String, List<String>) -> Task<Int>`. This touches the stdlib definition, the `__run_process` type-checker binding, the JVM codegen intrinsic, the `KRuntime.runProcess()` Java implementation, and every Kestrel call site. After this story, callers must `await` the result inside an `async` context.

## Current State

- **stdlib/kestrel/process.ks** — `export fun runProcess(program: String, args: List<String>): Int = __run_process(program, args)` (synchronous, blocks on `Process.waitFor()`).
- **compiler/src/typecheck/check.ts** — `__run_process` typed as `(String, List<String>) -> Int`.
- **compiler/src/jvm-codegen/codegen.ts** — Emits `INVOKESTATIC KRuntime.runProcess(Object, Object)Long`.
- **runtime/jvm/src/.../KRuntime.java** — `runProcess()` builds a `ProcessBuilder`, starts the process, forwards stdout/stderr, and calls `waitFor()` — all blocking on the calling thread.
- **Callers (6 call sites)**:
  - `scripts/run_tests.ks:122,124` — test runner compiles and runs test scripts.
  - `tests/perf/float/run.ks:18,19,50,62` — performance benchmark runner.

## Relationship to other stories

- **Depends on S01-01 and S01-02**: KTask class and virtual-thread executor.
- **Depends on S01-03 (partially)**: Establishes the virtual-thread I/O pattern.
- **Interacts with S01-04**: A `ProcessError` ADT could follow the same `Task<Result<Int, ProcessError>>` pattern. This story uses provisional error handling (exceptions).
- **Parallel with S01-07 and S01-08**: Independent API-migration stories.

## Goals

1. **Stdlib signature**: `export async fun runProcess(program: String, args: List<String>): Task<Int> = __run_process_async(program, args)` (or rename the intrinsic).
2. **Type-checker binding**: `__run_process` (or new `__run_process_async`) returns `Task<Int>`.
3. **JVM codegen**: Emit `INVOKESTATIC KRuntime.runProcessAsync(Object, Object)Object` returning a `KTask`.
4. **KRuntime.java**: `runProcessAsync()` submits the process execution to the virtual-thread executor and returns a `KTask<Int>` backed by `CompletableFuture`. The virtual thread runs `ProcessBuilder.start()` + `waitFor()` — under Loom this unmounts the carrier thread during the blocking `waitFor()`.
5. **Caller cascade — run_tests.ks**: Convert calls at lines 122 and 124 to use `await`; ensure enclosing functions are `async`. This script also uses `listDir` and `writeText`, so if S01-07 and S01-08 are done first, the script may already be async.
6. **Caller cascade — tests/perf/float/run.ks**: Convert all 4 `runProcess` call sites to use `await`; make enclosing functions `async`.
7. **Provisional errors**: On process launch failure, the KTask completes exceptionally. Stub: TODO referencing a future story for `Result<Int, ProcessError>` if needed.

## Acceptance Criteria

- [ ] `Process.runProcess("prog", args)` returns `Task<Int>`; callers use `await`.
- [ ] `stdlib/kestrel/process.ks` signature updated.
- [ ] `__run_process` type binding in `compiler/src/typecheck/check.ts` returns `Task<Int>`.
- [ ] JVM codegen emits the async variant returning a `KTask`.
- [ ] `KRuntime.java` `runProcessAsync()` dispatches to the virtual-thread executor.
- [ ] `scripts/run_tests.ks` updated: both `runProcess` calls use `await`, enclosing functions are `async`.
- [ ] `tests/perf/float/run.ks` updated: all 4 `runProcess` calls use `await`, enclosing code is `async`.
- [ ] `docs/specs/02-stdlib.md` `runProcess` entry updated to reflect `Task<Int>` signature (if documented).
- [ ] Error on launch failure: `KTask.get()` throws; at least one test verifies.
- [ ] All test suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/02-stdlib.md` (`kestrel:process` — `runProcess` signature, if documented)
- `docs/specs/01-language.md` §5 (Async and Task model)

## Risks / Notes

- **Process I/O forwarding**: Today `runProcess` reads the subprocess stdout/stderr on the calling thread and writes it to `System.out`. Under the async model this still happens on the virtual thread — behavior is unchanged except that the calling Kestrel thread is not blocked.
- **run_tests.ks is heavily impacted**: This script calls `listDir` (S01-07), `writeText` (S01-08), and `runProcess` (this story). If all three stories are implemented, `run_tests.ks` becomes fully async. The stories can be done in any order — each adds `await` at its own call sites and makes functions async as needed.
- **perf runner**: `tests/perf/float/run.ks` runs benchmarks sequentially via `runProcess`. Making calls async with `await` preserves sequential semantics — no behavior change, just the virtual-thread scheduling underneath.
- **getProcess stays sync**: The user mentioned `getProcess` — this function reads `os`, `args`, `cwd` from environment variables/system properties, which are instant and non-blocking. It does not need to become async. It remains `() -> P` (a record type).
