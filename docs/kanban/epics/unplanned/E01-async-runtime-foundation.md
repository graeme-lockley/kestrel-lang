# Epic E01: Async Runtime Foundation

## Status

Unplanned

## Summary

Foundation epic for real async behavior on the JVM backend using **Java Project Loom** (virtual threads). Delivers a concrete `KTask` runtime type, a virtual-thread executor for genuine async function dispatch, non-blocking I/O, typed error handling via `Result<T, E>` ADTs, CLI process-lifetime flags, and comprehensive specs and tests. Unblocks Epic E02 (HTTP / networking).

## Implementation Approach

Async execution exploits **Project Loom virtual threads** (Java 21+) rather than a hand-rolled event loop or continuation-passing transform. `async fun` bodies dispatch to virtual threads; `await` blocks the calling virtual thread cheaply (the JVM unmounts the carrier thread). This removes the need for explicit state-machine codegen or AWAIT opcodes.

## Stories (ordered — implement sequentially)

1. [x] [S01-01-ktask-runtime-class-and-codegen-wiring.md](../../done/S01-01-ktask-runtime-class-and-codegen-wiring.md) — KTask Java class, completedTask() update, await codegen wiring. Completed.
2. [S01-02-virtual-thread-executor-async-launch.md](../../unplanned/S01-02-virtual-thread-executor-async-launch.md) — Virtual thread executor; async function bodies launch on virtual threads; await blocks cheaply.
3. [S01-03-nonblocking-file-io-virtual-threads.md](../../unplanned/S01-03-nonblocking-file-io-virtual-threads.md) — readFileAsync on virtual threads; provisional error handling (exceptions).
4. [S01-07-async-listdir-cascade.md](../../unplanned/S01-07-async-listdir-cascade.md) — Async `listDir` signature, JVM runtime, codegen, and cascade all Kestrel callers (fs.test.ks, run_tests.ks).
5. [S01-08-async-writetext-cascade.md](../../unplanned/S01-08-async-writetext-cascade.md) — Async `writeText` signature, JVM runtime, codegen, and cascade all Kestrel callers (fs.test.ks, run_tests.ks).
6. [S01-09-async-runprocess-cascade.md](../../unplanned/S01-09-async-runprocess-cascade.md) — Async `runProcess` signature, JVM runtime, codegen, and cascade all Kestrel callers (run_tests.ks, perf runner).
7. [S01-04-result-error-adts-async-operations.md](../../unplanned/S01-04-result-error-adts-async-operations.md) — Result<T, E> and FsError ADT for typed async error handling; all async I/O returns Task<Result<T, E>>.
8. [S01-11-async-lambda-expressions.md](../../unplanned/S01-11-async-lambda-expressions.md) — Grammar, AST, type checker, and codegen for `async (params) => body` lambda expressions; `await` in a non-async lambda remains a compile error.
9. [S01-10-async-test-harness-suite-runner.md](../../unplanned/S01-10-async-test-harness-suite-runner.md) — Standardize all test suite `run` functions to `async fun run(s: Suite): Task<Unit>` and update the generated test runner to `await` each call.
10. [S01-05-cli-exit-wait-exit-no-wait.md](../../unplanned/S01-05-cli-exit-wait-exit-no-wait.md) — CLI --exit-wait (default) and --exit-no-wait flags for process lifetime.
11. [S01-06-specs-conformance-e2e-tests.md](../../unplanned/S01-06-specs-conformance-e2e-tests.md) — Spec updates, conformance tests, and E2E scenarios for the full async model.

Stories 4–6 (listDir, writeText, runProcess) can be implemented in any order relative to each other; they all depend on S01-03. S01-11 and S01-10 should follow those three.

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
