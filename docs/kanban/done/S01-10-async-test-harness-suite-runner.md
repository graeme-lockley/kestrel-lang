# Async-Aware Test Harness and Suite Runner

## Sequence: S01-10
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/done/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-06, S01-07, S01-08, S01-09

## Summary

Standardize all Kestrel test suite `run` functions to `async fun run(s: Suite): Task<Unit>` and update the test runner (`scripts/run_tests.ks`) to generate `await` calls so async suites are correctly executed. Currently `fs.test.ks` already declares `async fun run(...)` but the runner generates bare `run${idx}(root)` calls — no `await`. With S01-02 landing, async suite functions will dispatch to virtual threads and the task will be silently abandoned. After S01-07/08/09, further test files will also require async `run` functions.

## Current State

- **`stdlib/kestrel/fs.test.ks`**: `export async fun run(s: Suite): Task<Unit>` — correctly async because it uses `await Fs.readText(...)`.
- **All other stdlib test files** (`basics.test.ks`, `string.test.ks`, `list.test.ks`, etc.): `export fun run(s: Suite): Unit` — synchronous.
- **`scripts/run_tests.ks` — `buildCalls`**: Generates `run${idx}(root)\n` for every suite — no `await`, no async context.
- **Why it works today**: Tasks complete synchronously; calling a `Task<Unit>` without `await` still runs the body immediately. After S01-02 (virtual threads), the task body dispatches to a virtual thread and the generated runner continues to the next suite before the previous one finishes.
- **After S01-07/08/09**: `fs.test.ks`, and any other test files that use `listDir`, `writeText`, or `runProcess`, will also have async `run` functions. The runner is not prepared for this.

## Relationship to other stories

- **Depends on S01-02**: Virtual thread executor must exist for the latent bug to manifest. Can be implemented alongside or just after S01-02.
- **Logically follows S01-07, S01-08, S01-09**: Those stories make more test files async; this story fixes the runner to handle them.
- **Enables S01-06**: Conformance and E2E tests in S01-06 need the test harness to be correct.
- **Does not require async lambdas**: The fix uses named async functions throughout — no parser changes.

## Goals

1. **Standardize suite signature**: All stdlib test suites (`*.test.ks`) use `async fun run(s: Suite): Task<Unit>`. Sync suites become async by wrapping their body (no actual async work — the Task is immediately completed by the virtual-thread executor).
2. **Update `buildCalls`**: `scripts/run_tests.ks` generates `await run${idx}(root)` instead of `run${idx}(root)`.
3. **Async generated runner**: The generated `_test_runner.ks` wraps all suite invocations in an async context (e.g. `async fun main(): Task<Unit> = { await run0(root); await run1(root); ... }`).
4. **Test harness spec (`test.ks`)**: If `test.ks` exports a helper that runs suites, update it if needed. Otherwise no change — `Suite` itself stays synchronous (it's a record, not an execution handle).
5. **All test suites in stdlib updated**: Review `basics.test.ks`, `char.test.ks`, `dict.test.ks`, `json.test.ks`, all other `*.test.ks` — convert sync `run` functions to async.
6. **`docs/specs/08-tests.md` updated**: Document that suite `run` functions must return `Task<Unit>` and are invoked with `await` by the test runner.

## Acceptance Criteria

- [x] Every `stdlib/kestrel/*.test.ks` exports `async fun run(s: Suite): Task<Unit>`.
- [x] Every `tests/unit/*.test.ks` exports `async fun run(s: Suite): Task<Unit>`.
- [x] `scripts/run_tests.ks` `buildCalls` generates `await run${idx}(root)`.
- [x] The generated test runner script is valid Kestrel in an async context (entry point is async or top-level `await` is valid).
- [x] `./scripts/kestrel test` still runs all suites and produces correct pass/fail counts.
- [x] `docs/specs/08-tests.md` updated: suite `run` signature documented as `Task<Unit>`.
- [x] No suite's test results are silently lost due to un-awaited tasks.
- [x] All test suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/08-tests.md` (test suite structure, run function signature)
- `docs/specs/01-language.md` §5 (Async and Task model — await semantics)

## Risks / Notes

- **Top-level await**: The generated runner currently calls suites at top level (not inside a function). If Kestrel does not support `await` at module top level, the generated runner needs a named `async fun main(): Task<Unit>` entry point. Verify the current behaviour.
- **Suite count of test files**: There are ~15 stdlib test files and ~15+ unit test files. Each needs its `run` function converted. This is mechanical but must be done completely — any missed file will be detected as a type mismatch when the runner calls `await run${idx}(root)`.
- **Compile-time type safety**: After this change, if a new test file is added with a sync `run`, the generated runner will fail to type-check (calling `await` on a `Unit` value). This is a good thing — it enforces the contract.
- **No async lambdas needed**: This story uses only named `async fun` declarations. Async lambda support (parser/AST changes) is a separate language-ergonomics feature not in scope for Epic E01.
- **Conversion of sync suites is trivial**: `export fun run(s: Suite): Unit = { ... }` becomes `export async fun run(s: Suite): Task<Unit> = { ... }` — no other changes needed for suites that don't currently call async APIs.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler parser (`compiler/src/parser/parse.ts`) | No source change expected. Existing `await` parsing is sufficient; generated runner must keep all `await` expressions inside an `async fun` body to satisfy current grammar+context rules. |
| Compiler typechecker (`compiler/src/typecheck/check.ts`) | No source change expected. Existing `AwaitExpr` validation already enforces async context and `Task<T>` input. This story intentionally relies on type errors as a guardrail when a suite keeps a sync `run`. |
| JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | No source change expected. Existing async lowering (`submitAsync`, `AwaitExpr` to `KTask.get()`) should be exercised by generated test runner code after script updates. |
| JVM runtime (`runtime/jvm/src/kestrel/runtime/KRuntime.java`, `runtime/jvm/src/kestrel/runtime/KTask.java`) | No runtime API change expected. Current virtual-thread executor and `KTask.get()` semantics are prerequisites that make un-awaited suite tasks unsafe, which this story addresses at harness level. |
| Stdlib test harness (`stdlib/kestrel/test.ks`) | Likely no functional change to `Suite` shape or assertion helpers. Confirm no helper assumes sync suite entrypoints. Compatibility risk is low because `Suite` remains a plain record passed by reference. |
| Stdlib test suites (`stdlib/kestrel/*.test.ks`) | Convert remaining sync `run` signatures to `async fun run(s: Suite): Task<Unit>` (currently 11 sync, 2 async). Mechanical edits across all suites; rollback is straightforward but would reintroduce latent dropped-task behaviour. |
| Unit test suites (`tests/unit/*.test.ks`) | Convert remaining sync `run` signatures to `async fun run(s: Suite): Task<Unit>` (currently 31 sync, 2 async). This bakes async contract into harness corpus and catches future drift at compile time. |
| Test runner script (`scripts/run_tests.ks`) | Update `buildCalls` to emit `await runN(root)` and generate async runner wrapper (`async fun main(): Task<Unit> = { ... }`) so calls are valid and sequentially awaited. This is the primary behaviour change. |
| CLI test entrypoint (`scripts/kestrel`) | No direct code change expected; `kestrel test` continues compiling/executing `scripts/run_tests.ks`. Verify user-facing output stability and pass/fail counts remain correct. |
| Specs and docs (`docs/specs/08-tests.md`, `docs/specs/01-language.md`) | Update test-plan contract to require async suite signatures and awaited invocation in generated runner; ensure language-spec references remain accurate for async-context `await` constraints. |

## Tasks

- [x] Confirm parser/typecheck/codegen prerequisites need no implementation changes by compiling a generated runner shape that uses `await runN(root)` only inside `async fun main(): Task<Unit>`.
- [x] Update `scripts/run_tests.ks` `buildCalls` to generate `await run${idx}(root)` lines.
- [x] Update `scripts/run_tests.ks` generated source template so suite calls execute inside an async entrypoint and `printSummary(counts)` runs after all awaited suites complete.
- [x] Verify `stdlib/kestrel/test.ks` needs no API/signature changes for async suite execution; if needed, adjust helper signatures without changing `Suite` record shape.
- [x] Convert every sync stdlib suite entrypoint in `stdlib/kestrel/*.test.ks` from `export fun run(s: Suite): Unit` to `export async fun run(s: Suite): Task<Unit>` (leave existing async files intact).
- [x] Convert every sync unit suite entrypoint in `tests/unit/*.test.ks` from `export fun run(s: Suite): Unit` to `export async fun run(s: Suite): Task<Unit>` (leave existing async files intact).
- [x] Update/extend harness-focused coverage in `tests/unit/harness_output.test.ks` (or a dedicated new unit suite) so async `run` signature and grouped output paths are exercised.
- [x] Add an integration regression in `compiler/test/integration/runtime-stdlib.test.ts` or `compiler/test/integration/jvm-async-runtime.test.ts` that fails if generated test-runner suite calls are not awaited.
- [x] Update `docs/specs/08-tests.md` to define suite contract as `async fun run(s: Suite): Task<Unit>` and clarify that runner invocation is awaited.
- [x] Validate compiler suite: `cd compiler && npm run build && npm test`.
- [x] Validate JVM runtime jar: `cd runtime/jvm && bash build.sh`.
- [x] Validate Kestrel harness suite: `./scripts/kestrel test`.
- [x] Validate user-visible E2E behaviour: `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/jvm-async-runtime.test.ts` | Add a regression that emulates generated runner sequencing and proves awaited suite calls complete before summary/exit. |
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Add a harness-oriented case that compiles async suite-style code and verifies `Task<Unit>` run contract composes with existing stdlib async APIs. |
| Kestrel harness | `tests/unit/harness_output.test.ks` | Convert to async `run` and keep nested group assertions so output formatting still works under async suite entrypoints. |
| Kestrel harness | `tests/unit/async_virtual_threads.test.ks` | Extend with a small contract check that suite-level async work must be awaited to affect observed assertions/output. |
| Kestrel harness | `stdlib/kestrel/*.test.ks` and `tests/unit/*.test.ks` | Add/retain compile-time contract coverage by standardizing all suite entrypoints to async; any future sync `run` should fail during generated-runner typecheck. |

## Documentation and specs to update

- [x] `docs/specs/08-tests.md` — In the stdlib suite/harness sections, document canonical suite signature as `async fun run(s: Suite): Task<Unit>` and that generated runner calls are awaited.
- [x] `docs/specs/01-language.md` — In Section 5, add a brief note that harness-generated `await` calls run inside async entrypoints (no top-level await requirement) and remain subject to async-context rules.

## Notes

- Current inventory confirms migration scale: `stdlib/kestrel/*.test.ks` has 13 suites total (11 sync, 2 async), and `tests/unit/*.test.ks` has 33 suites total (31 sync, 2 async).
- `scripts/run_tests.ks` already has async helper functions (`listDirOrExit`, `writeTextOrExit`, `runProcessOrExit`) and an async `main`; the remaining correctness gap is generated suite-call awaiting.

## Build notes

- 2026-04-03: Started implementation by moving S01-10 from planned to doing and confirming impact-analysis assumptions still matched current runner/typecheck behavior.
- 2026-04-03: Updated `scripts/run_tests.ks` to generate `await runN(root)` calls inside generated `async fun main(): Task<Unit>`; this removed top-level suite invocation ordering risk.
- 2026-04-03: Initial generated-runner shape failed with `printSummary(counts)` parsed as callable before trailing `()`; fixed by emitting `printSummary(counts);` with an explicit statement terminator.
- 2026-04-03: Added integration guard in `compiler/test/integration/runtime-stdlib.test.ts` to assert generated runner source contains async main plus awaited suite calls and no bare `runN(root)` lines.
