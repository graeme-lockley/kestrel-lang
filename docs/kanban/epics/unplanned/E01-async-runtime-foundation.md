# Epic E01: Async Runtime Foundation

## Status

Unplanned

## Summary

Foundation epic for real async behavior on the JVM backend using **Java Project Loom** (virtual threads). Delivers a concrete `KTask` runtime type, a virtual-thread executor for genuine async function dispatch, non-blocking I/O, typed error handling via `Result<T, E>` ADTs, CLI process-lifetime flags, and comprehensive specs and tests. Unblocks Epic E02 (HTTP / networking).

## Implementation Approach

Async execution exploits **Project Loom virtual threads** (Java 21+) rather than a hand-rolled event loop or continuation-passing transform. `async fun` bodies dispatch to virtual threads; `await` blocks the calling virtual thread cheaply (the JVM unmounts the carrier thread). This removes the need for explicit state-machine codegen or AWAIT opcodes.

## Stories (ordered — implement sequentially)

1. [x] [S01-01-ktask-runtime-class-and-codegen-wiring.md](../../done/S01-01-ktask-runtime-class-and-codegen-wiring.md) — KTask Java class, completedTask() update, await codegen wiring. Completed.
2. [x] [S01-02-virtual-thread-executor-async-launch.md](../../done/S01-02-virtual-thread-executor-async-launch.md) — Virtual thread executor; async function bodies launch on virtual threads; await blocks cheaply. Completed.
3. [x] [S01-03-nonblocking-file-io-virtual-threads.md](../../done/S01-03-nonblocking-file-io-virtual-threads.md) — readFileAsync on virtual threads; provisional error handling (exceptions). Completed.
4. [x] [S01-07-async-listdir-cascade.md](../../done/S01-07-async-listdir-cascade.md) — Async `listDir` signature, JVM runtime, codegen, and cascade all Kestrel callers (fs.test.ks, run_tests.ks). Completed.
5. [x] [S01-08-async-writetext-cascade.md](../../done/S01-08-async-writetext-cascade.md) — Async `writeText` signature, JVM runtime, codegen, and cascade all Kestrel callers (fs.test.ks, run_tests.ks). Completed.
6. [x] [S01-09-async-runprocess-cascade.md](../../done/S01-09-async-runprocess-cascade.md) — Async `runProcess` signature, JVM runtime, codegen, and cascade all Kestrel callers (run_tests.ks, perf runner). Completed.
7. [x] [S01-04-result-error-adts-async-operations.md](../../done/S01-04-result-error-adts-async-operations.md) — Result<T, E> and FsError ADT for typed async error handling; all async I/O returns Task<Result<T, E>>. Completed.
8. [x] [S01-11-async-lambda-expressions.md](../../done/S01-11-async-lambda-expressions.md) — Grammar, AST, type checker, and codegen for `async (params) => body` lambda expressions; `await` in a non-async lambda remains a compile error. Completed.
9. [x] [S01-10-async-test-harness-suite-runner.md](../../done/S01-10-async-test-harness-suite-runner.md) — Standardize all test suite `run` functions to `async fun run(s: Suite): Task<Unit>` and update the generated test runner to `await` each call. Completed.
10. [x] [S01-05-cli-exit-wait-exit-no-wait.md](../../done/S01-05-cli-exit-wait-exit-no-wait.md) — CLI --exit-wait (default) and --exit-no-wait flags for process lifetime. Completed.
11. [x] [S01-06-specs-conformance-e2e-tests.md](../../done/S01-06-specs-conformance-e2e-tests.md) — Spec updates, conformance tests, and E2E scenarios for the full async model. Completed.
12. [x] [S01-12-block-local-async-fun.md](../../done/S01-12-block-local-async-fun.md) — Support `async fun` at block scope (FunStmt); grammar, AST, type-checker, codegen.
13. [x] [S01-13-task-combinator-api.md](../../done/S01-13-task-combinator-api.md) — Add `Task.all`, `Task.race`, and `Task.map` combinators to stdlib and runtime.
14. [x] [S01-14-in-async-context-param-refactor.md](../../done/S01-14-in-async-context-param-refactor.md) — Refactor `inAsyncContext` from mutable closure state into an explicit parameter on `inferExpr`.
15. [x] [S01-15-await-parser-dead-branch-cleanup.md](../../done/S01-15-await-parser-dead-branch-cleanup.md) — Remove dead `CallExpr` branch in the `await` / `parsePrimary` parser path.
16. [x] [S01-16-await-type-error-message.md](../../done/S01-16-await-type-error-message.md) — Improve `await`-on-non-Task diagnostic to include the actual resolved type.
17. [x] [S01-17-task-cancellation-api.md](../../done/S01-17-task-cancellation-api.md) — Expose task cancellation via `Task.cancel` backed by `CompletableFuture.cancel()`.
18. [ ] [S01-18-run-process-stdout-capture.md](../../unplanned/S01-18-run-process-stdout-capture.md) — Return captured stdout string from `runProcess`; update result ADT and stdlib.
19. [ ] [S01-19-listdir-direntry-adt.md](../../unplanned/S01-19-listdir-direntry-adt.md) — Replace raw tab-embedded strings from `listDir` with a typed `DirEntry` ADT.
20. [ ] [S01-20-scc-trampoline-async-fix.md](../../unplanned/S01-20-scc-trampoline-async-fix.md) — Preserve trampoline optimization for sync members of SCCs that contain async functions.
21. [ ] [S01-21-async-quiescence-counter-contention.md](../../unplanned/S01-21-async-quiescence-counter-contention.md) — Replace `asyncTasksInFlight` monitor with `LongAdder`/`Phaser` to reduce lock contention.
22. [ ] [S01-22-await-behavior-validation-real-tests.md](../../unplanned/S01-22-await-behavior-validation-real-tests.md) — Replace placeholder `1 == 1` assertions in `await-behavior-validation.test.ks` with real behavioral tests.
23. [ ] [S01-23-async-module-interface-docs.md](../../unplanned/S01-23-async-module-interface-docs.md) — Document async semantics and structural async typing in the module system spec.

Stories 4–6 (listDir, writeText, runProcess) can be implemented in any order relative to each other; they all depend on S01-03. S01-11 and S01-10 should follow those three. Stories S01-12–S01-23 address gaps identified in the post-delivery critical analysis and can be tackled in any order unless otherwise noted.

## Stub Strategy

Each story may stub dependencies on later stories with TODO errors (e.g. S01-01 stubs virtual-thread suspension with a TODO referencing S01-02). Stubs are resolved by the referenced story.

## Dependencies

- Unblocks Epic E02 for robust async networking behavior.
- Requires **Java 21+** for Project Loom virtual threads (documented from S01-02 onward).

## Epic Completion Criteria

- All eleven stories (S01-01 through S01-11) are in `done/`.
- Virtual thread executor drives async functions and lambdas on the JVM.
- `readText`, `listDir`, `writeText`, and `runProcess` are all async with typed Result errors.
- All Kestrel callers updated to `await` (stdlib tests, run_tests.ks, perf runner).
- Async lambda expressions (`async (params) => body`) compile and execute correctly; `await` in a non-async lambda is a compile error.
- All test suite `run` functions are `async fun run(s: Suite): Task<Unit>`; test runner awaits each.
- CLI exit flags documented and working.
- Specs accurate; conformance and E2E tests passing.
- `cd compiler && npm run build && npm test`, `./scripts/kestrel test`, `./scripts/run-e2e.sh` all green.
- Block-local `async fun` compiles and executes correctly (S01-12).
- `Task.all`, `Task.race`, and `Task.map` combinators available in stdlib with tests (S01-13).
- `inAsyncContext` passed as explicit parameter to `inferExpr`; no mutable module-level state (S01-14).
- Dead `CallExpr` branch removed from `parsePrimary` await path (S01-15).
- `await`-on-non-Task diagnostic includes the actual resolved type (S01-16).
- `Task.cancel()` backed by `CompletableFuture.cancel()` and accessible from Kestrel (S01-17).
- `runProcess` returns captured stdout; result ADT and stdlib updated (S01-18).
- `listDir` returns `List<DirEntry>` ADT; raw tab-string format retired (S01-19).
- Trampoline optimization applied to sync SCC members even when async members are present (S01-20).
- `asyncTasksInFlight` uses `LongAdder`/`Phaser`; `synchronized(asyncMonitor)` removed (S01-21).
- `await-behavior-validation.test.ks` contains only real behavioral assertions; no `1 == 1` stubs (S01-22).
- Module system spec documents async structural typing and `async fun` interface rules (S01-23).
