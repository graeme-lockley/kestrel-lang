# Async-Aware Test Harness and Suite Runner

## Sequence: S01-10
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
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

- [ ] Every `stdlib/kestrel/*.test.ks` exports `async fun run(s: Suite): Task<Unit>`.
- [ ] Every `tests/unit/*.test.ks` exports `async fun run(s: Suite): Task<Unit>`.
- [ ] `scripts/run_tests.ks` `buildCalls` generates `await run${idx}(root)`.
- [ ] The generated test runner script is valid Kestrel in an async context (entry point is async or top-level `await` is valid).
- [ ] `./scripts/kestrel test` still runs all suites and produces correct pass/fail counts.
- [ ] `docs/specs/08-tests.md` updated: suite `run` signature documented as `Task<Unit>`.
- [ ] No suite's test results are silently lost due to un-awaited tasks.
- [ ] All test suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/08-tests.md` (test suite structure, run function signature)
- `docs/specs/01-language.md` §5 (Async and Task model — await semantics)

## Risks / Notes

- **Top-level await**: The generated runner currently calls suites at top level (not inside a function). If Kestrel does not support `await` at module top level, the generated runner needs a named `async fun main(): Task<Unit>` entry point. Verify the current behaviour.
- **Suite count of test files**: There are ~15 stdlib test files and ~15+ unit test files. Each needs its `run` function converted. This is mechanical but must be done completely — any missed file will be detected as a type mismatch when the runner calls `await run${idx}(root)`.
- **Compile-time type safety**: After this change, if a new test file is added with a sync `run`, the generated runner will fail to type-check (calling `await` on a `Unit` value). This is a good thing — it enforces the contract.
- **No async lambdas needed**: This story uses only named `async fun` declarations. Async lambda support (parser/AST changes) is a separate language-ergonomics feature not in scope for Epic E01.
- **Conversion of sync suites is trivial**: `export fun run(s: Suite): Unit = { ... }` becomes `export async fun run(s: Suite): Task<Unit> = { ... }` — no other changes needed for suites that don't currently call async APIs.
