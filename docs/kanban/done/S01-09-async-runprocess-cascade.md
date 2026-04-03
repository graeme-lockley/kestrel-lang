# Async runProcess — Signature, Callers, and Cascade

## Sequence: S01-09
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-06, S01-07, S01-08

## Summary

Promote the stale `runProcess` migration story to a build-ready plan that matches the current repository. The original draft targeted a pre-S01-04 midpoint where `Process.runProcess` would become `Task<Int>` with provisional exception-based failures. The repo has already moved beyond that point: the public API is now `Task<Result<Int, ProcessError>>`, the JVM runtime exposes `KRuntime.runProcessAsync`, and the known Kestrel callers already `await` the result. This story now scopes the remaining work to auditing that end-to-end path, filling runProcess-specific regression gaps, and removing documentation drift without regressing the final Result-based surface.

## Current State

- **stdlib/kestrel/process.ks** — `export async fun runProcess(program: String, args: List<String>): Task<Result<Int, ProcessError>>` awaits `__run_process(program, args)` and maps raw `process_error:` codes into the public `ProcessError` ADT.
- **compiler/src/typecheck/check.ts** — `__run_process` is typed as `(String, List<String>) -> Task<Result<Int, String>>`; the intrinsic exposes runtime error codes as `String`, and the stdlib wrapper upgrades them to `ProcessError`.
- **compiler/src/jvm-codegen/codegen.ts** — `__run_process` lowers to `INVOKESTATIC KRuntime.runProcessAsync(Object, Object): KTask`.
- **runtime/jvm/src/kestrel/runtime/KRuntime.java** — `runProcessAsync()` submits subprocess execution to the virtual-thread executor, merges stderr into stdout, forwards child output to `System.out`, and completes the task with `KOk(exitCode)` on success or `KErr("process_error:...")` on failure.
- **Callers already migrated**:
  - `scripts/run_tests.ks` awaits `runProcess(...)` through `runProcessOrExit()` for both the generated-runner `cmp`/`mv` shell step and the final `./scripts/kestrel run ...` invocation.
  - `tests/perf/float/run.ks` awaits `Process.runProcess(...)` through `runProcessCode()` while preserving sequential benchmark order.
  - `stdlib/kestrel/process.test.ks` already awaits `Process.runProcess(...)` for both exit-code and missing-binary coverage.
- **Coverage gap**: There is no runProcess-specific JVM integration regression in `compiler/test/integration/runtime-stdlib.test.ts`, and there is no focused E2E scenario that pins output forwarding plus `Result` behavior for the public `kestrel:process` surface.

## Relationship to other stories

- **Depends on S01-02 and S01-03**: `runProcessAsync()` relies on the `KTask` runtime and virtual-thread executor already delivered there.
- **Depends on S01-04**: This story must preserve the final `Task<Result<Int, ProcessError>>` surface introduced by typed async error handling. It must not regress to the obsolete `Task<Int>` or exception-first design captured in the stale unplanned draft.
- **Parallel with S01-07 and S01-08**: `scripts/run_tests.ks` is shared fallout across the async fs/process migrations, so changes here must not conflict with the `listDir` and `writeText` cascades.
- **Interacts with S01-10**: The test-runner script already awaits process helpers, but suite invocation remains a separate harness concern handled by S01-10.
- **Follows S01-06**: Canonical specs already describe the async `Result` model; this story is now about aligning implementation coverage and story records with those specs.

## Goals

1. **Keep the final public surface**: `Process.runProcess(program, args)` remains `Task<Result<Int, ProcessError>>`; callers `await` and pattern-match rather than relying on synchronous blocking semantics or thrown process-launch failures.
2. **Verify intrinsic alignment**: The compiler type checker, JVM codegen, JVM runtime, and stdlib wrapper all agree on the `__run_process` contract and payload shape.
3. **Preserve caller behavior**: `scripts/run_tests.ks` and `tests/perf/float/run.ks` continue to work with awaited `runProcess` results and keep their current failure/reporting behavior.
4. **Close runProcess-specific coverage gaps**: Add or extend automated tests so exit-code delivery, output forwarding, and spawn-failure behavior are covered at the JVM integration and user-visible CLI/E2E layers.
5. **Remove planning drift**: The story text, spec references, and follow-up notes reflect the current post-S01-04 implementation instead of the obsolete provisional migration plan.

## Acceptance Criteria

- [x] `stdlib/kestrel/process.ks` continues to export `runProcess(program: String, args: List<String>): Task<Result<Int, ProcessError>>` and maps runtime error codes to `ProcessError` consistently.
- [x] `compiler/src/typecheck/check.ts` `__run_process` binding remains aligned with the runtime contract: `(String, List<String>) -> Task<Result<Int, String>>` at the intrinsic layer, with stdlib mapping to `ProcessError` at the public layer.
- [x] `compiler/src/jvm-codegen/codegen.ts` emits the async intrinsic call to `KRuntime.runProcessAsync(Object, Object): KTask` for `__run_process`.
- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java` `runProcessAsync()` dispatches to the virtual-thread executor, forwards subprocess output, and returns `KOk(exitCode)` / `KErr(code)` rather than blocking the caller thread or surfacing expected launch failures as user-visible uncaught exceptions.
- [x] `scripts/run_tests.ks` continues to await both `runProcess` call sites and preserves current non-zero exit behavior when child-process startup fails.
- [x] `tests/perf/float/run.ks` continues to await all `Process.runProcess(...)` calls and preserves sequential benchmark semantics.
- [x] `compiler/test/integration/runtime-stdlib.test.ts` includes runProcess-specific JVM integration coverage for combined output forwarding, exit-code delivery, and missing-binary failure.
- [x] A focused positive E2E scenario pins the public `kestrel:process` behavior end to end without depending on host-specific tools beyond the existing `sh` baseline already used in repo tests.
- [x] User-facing docs do not describe stale synchronous or pre-Result `runProcess` behavior.
- [x] Verification passes: `cd compiler && npm run build && npm test`, `cd runtime/jvm && bash build.sh`, `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

## Spec References

- `docs/specs/02-stdlib.md` (`kestrel:process` — `runProcess` contract)
- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/06-typesystem.md` §6 (typing of `await` over `Task<Result<...>>`)
- `docs/specs/09-tools.md` §2.4 (`kestrel test` generated runner and async helper flow)

## Risks / Notes

- **Story drift is material**: The original unplanned file no longer matches the repo. Implementation work must preserve the current Result-based API, not the obsolete `Task<Int>` midpoint.
- **Intrinsic/public boundary differs by design**: The intrinsic returns `String` error codes while the public stdlib surface returns `ProcessError`. Compiler, runtime, and stdlib changes must stay synchronized or callers will see mismatched error semantics.
- **Shared runner fallout**: `scripts/run_tests.ks` is also touched by S01-07 and S01-08. Keep this story scoped to process-launch behavior and avoid accidental cross-story churn.
- **Output-forwarding assertions must stay stable**: The JVM runtime currently uses `redirectErrorStream(true)` and line-based forwarding to `System.out`. Tests should assert deterministic combined output markers and exit codes, not host-specific buffering quirks.
- **Perf runner semantics must stay sequential**: `tests/perf/float/run.ks` should keep awaiting each subprocess call in order; async scheduling must not accidentally overlap benchmark runs.
- **`getProcess` stays sync**: The process metadata accessor reads current-process state only and does not need any async migration in this story.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler typecheck | Audit `compiler/src/typecheck/check.ts` so the `__run_process` intrinsic stays `Task<Result<Int, String>>` and remains consistent with runtime error-code payloads. Compatibility risk: compile-time breakage if the intrinsic and wrapper drift; rollback is straightforward by restoring the prior intrinsic signature. |
| JVM codegen | Audit `compiler/src/jvm-codegen/codegen.ts` lowering for `__run_process` to ensure it still targets `KRuntime.runProcessAsync` with the correct descriptor. Risk is isolated to JVM backend runtime wiring. |
| JVM runtime | Audit or adjust `runtime/jvm/src/kestrel/runtime/KRuntime.java` `runProcessAsync()` so subprocess execution stays on the virtual-thread executor, output forwarding remains stable, and failures are encoded as `KErr("process_error:...")`. This is user-visible behavior; rollback risk is medium because it affects CLI/test-runner subprocess semantics. |
| Stdlib | Verify `stdlib/kestrel/process.ks` continues to expose the public `ProcessError`-typed API and that `mapProcessError` stays aligned with runtime codes. This is the compatibility boundary callers depend on. |
| Scripts | Verify `scripts/run_tests.ks` `runProcessOrExit()` keeps awaiting both child-process invocations and preserves current failure messaging. Shared-risk note: this file is also changed by S01-07/S01-08, so keep edits narrowly scoped. |
| Perf harness | Verify `tests/perf/float/run.ks` continues to await subprocesses sequentially so benchmark timing remains comparable before and after the audit. |
| Kestrel harness tests | Audit `stdlib/kestrel/process.test.ks`; extend it only if existing exit-code and spawn-error assertions miss a stable public-surface regression that belongs at the stdlib-test layer. |
| Vitest integration | Add runProcess-specific cases to `compiler/test/integration/runtime-stdlib.test.ts` so compiled JVM execution covers output forwarding, non-zero exit-code return, and missing-binary failure behavior independently of fs coverage. |
| E2E / user-visible behavior | Add a focused positive scenario under `tests/e2e/scenarios/positive/` that exercises `Process.runProcess(...)`, prints stable markers after forwarded child output, and handles a missing-binary `Err(ProcessSpawnError)` path without failing the outer scenario. |
| Specs and docs | Confirm `docs/specs/02-stdlib.md`, `docs/specs/01-language.md`, `docs/specs/06-typesystem.md`, and `docs/specs/09-tools.md` do not contradict the current async Result surface; update wording if any stale sync or exception-first language remains. |

## Tasks

- [x] Audit `compiler/src/typecheck/check.ts` `__run_process` typing so the intrinsic contract remains `Task<Result<Int, String>>` and matches the runtime payload shape.
- [x] Audit `compiler/src/jvm-codegen/codegen.ts` `__run_process` lowering to `KRuntime.runProcessAsync(Ljava/lang/Object;Ljava/lang/Object;)Lkestrel/runtime/KTask;` and fix any descriptor or intrinsic-name drift.
- [x] Audit `runtime/jvm/src/kestrel/runtime/KRuntime.java` `runProcessAsync()` for virtual-thread dispatch, combined output forwarding, and `KOk`/`KErr` payload shape; tighten failure handling if needed.
- [x] Audit `stdlib/kestrel/process.ks` `runProcess` wrapper and `mapProcessError` so the public surface remains `Task<Result<Int, ProcessError>>` and matches runtime error-code conventions.
- [x] Audit `scripts/run_tests.ks` `runProcessOrExit()` and generated-runner launch flow so both child-process calls remain awaited and failure messaging stays unchanged.
- [x] Audit `tests/perf/float/run.ks` `runProcessCode()` and the warmup/measured loops so subprocess execution remains sequential and result handling stays unchanged.
- [x] Audit `stdlib/kestrel/process.test.ks` and extend it only if existing exit-code or spawn-error assertions are incomplete for the current public surface.
- [x] Add or extend `compiler/test/integration/runtime-stdlib.test.ts` with runProcess success/output-forwarding and missing-binary JVM integration regressions.
- [x] Add or extend a focused positive scenario under `tests/e2e/scenarios/positive/` if CLI-level runProcess behavior is not already pinned elsewhere.
- [x] Update canonical specs and any still-user-facing docs that describe stale sync or pre-Result `runProcess` behavior.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Compile and run JVM programs that `await Process.runProcess(...)`, asserting combined child output forwarding plus `Ok(exitCode)` for a shell command and `Err(ProcessSpawnError(_))` for a missing binary. |
| E2E positive | `tests/e2e/scenarios/positive/async-runprocess-result.ks` | Exercise the full CLI path by awaiting `Process.runProcess(...)`, printing stable markers after forwarded stdout/stderr, and confirming the missing-binary path returns `Err(ProcessSpawnError(_))` without crashing the outer program. |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — confirm the `kestrel:process` `runProcess` row describes the final `Task<Result<Int, ProcessError>>` contract and current output-forwarding/spawn-failure behavior.
- [x] `docs/specs/01-language.md` — keep the async/task model wording consistent with failure-as-data process tasks so this story does not reintroduce exception-first wording.
- [x] `docs/specs/06-typesystem.md` — confirm the `await` typing examples remain accurate for `Task<Result<...>>` process APIs.
- [x] `docs/specs/09-tools.md` — verify `kestrel test` still matches the async `scripts/run_tests.ks` implementation that launches child processes through awaited `runProcess` helpers.

## Notes

- The repository already appears to satisfy most of the original story mechanically. `build-story` should treat this as an audit-and-closeout task: add only the missing runProcess-specific regression coverage and docs cleanup that remain after verification.
- For process coverage, prefer `sh -c` commands that emit a few deterministic lines and exit with a known code, because the repo already assumes `sh` availability in tests and scripts.

## Build notes

- 2026-04-03: Started implementation.
- 2026-04-03: Audit confirmed implementation already aligned in compiler typecheck/codegen, JVM runtime, stdlib wrapper, test runner, and perf harness. Scope remained audit + regression coverage only.
- 2026-04-03: Added two integration regressions in `compiler/test/integration/runtime-stdlib.test.ts`: (1) combined stdout/stderr forwarding with `Ok(exitCode)` and (2) missing-binary `Err(ProcessSpawnError(_))`.
- 2026-04-03: Added focused E2E scenario `tests/e2e/scenarios/positive/async-runprocess-result.ks` (+ `.expected`) to pin public runProcess output forwarding and spawn-error handling end to end.
- 2026-04-03: Specs already matched the final API/semantics (`docs/specs/02-stdlib.md`, `docs/specs/01-language.md`, `docs/specs/06-typesystem.md`, `docs/specs/09-tools.md`), so no spec text changes were needed.
- 2026-04-03: Full required verification passed: `cd compiler && npm run build && npm test` (18 files, 217 tests), `cd runtime/jvm && bash build.sh`, `./scripts/kestrel test` (1002 passed), `./scripts/run-e2e.sh` (12 negative + 9 positive).