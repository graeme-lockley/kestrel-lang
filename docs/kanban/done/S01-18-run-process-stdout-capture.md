# Capture `runProcess` stdout as String

## Sequence: S01-18
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

`runProcess` currently prints subprocess stdout directly to `System.out` and returns only an exit code. There is no way to capture a subprocess's stdout as a Kestrel `String`. Programs that call subprocesses and need to inspect their output — test harnesses, build tools, shell-script-like programs — cannot do so without error-prone temp-file workarounds. This story changes `runProcess` to capture stdout and return it alongside the exit code.

## Current State

```java
// KRuntime.java — runProcessAsync
while ((line = br.readLine()) != null) {
    System.out.println(line);   // printed directly, not returned
}
future.complete(new KOk(Long.valueOf(p.waitFor())));
```

```kestrel
// process.ks
export async fun runProcess(program: String, args: List<String>): Task<Result<Int, ProcessError>>
```

The Kestrel return type is `Task<Result<Int, ProcessError>>` — only the exit code.

## Relationship to other stories

- Depends on S01-04 (Result/ProcessError ADTs) and S01-09 (runProcess cascade).
- This is a breaking change to the `runProcess` API; all callers must be updated.
- E02 (HTTP) test helpers may use `runProcess` for curl/wget scripting — they will benefit.

## Goals

1. `KRuntime.runProcessAsync` captures stdout into a `StringBuilder` and includes it in the result.
2. The Kestrel result type changes to `Task<Result<{exitCode: Int, stdout: String}, ProcessError>>` or a named `ProcessResult` ADT.
3. `stdlib/kestrel/process.ks` updated, including `ProcessResult` type definition.
4. All callers of `runProcess` in the repo updated (tests, run_tests.ks, perf runner).
5. stderr handling: captured alongside stdout, or documented as "not captured" — decision recorded in spec.

## Acceptance Criteria

- `match (await Process.runProcess("echo", ["hello"])) { Ok(r) => r.stdout, Err(_) => "" }` returns `"hello\n"` (or `"hello"` with stripping).
- Existing callers that only inspect exit code compile and run without change (if `ProcessResult` record is used).
- Conformance or unit test verifies stdout capture.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- `docs/specs/02-stdlib.md` — update `runProcess` signature and describe `ProcessResult`.
- `docs/specs/01-language.md` §5 — update example if it references the old signature.

## Risks / Notes

- Stdout capture removes the live-streaming behaviour (lines no longer appear progressively during execution). For long-running subprocesses, this may be surprising. Consider an option flag or a separate `runProcessStreaming` variant.
- stderr is captured by many UNIX tools as the primary output channel (e.g. `rustc`). Decide whether to capture stderr separately, merge with stdout, or document as not captured.
- This is a breaking API change; callers in the stdlib test suite and run_tests.ks must be cascade-updated.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime (`KRuntime.java`) | `runProcessAsync` captures stdout+stderr into `StringBuilder`; wraps result as `KRecord` `{exitCode, stdout}` inside `KOk` |
| Stdlib (`process.ks`) | Add `ProcessResult` record type alias; update `runProcess` return signature to `Task<Result<ProcessResult, ProcessError>>` |
| All Kestrel callers | Update pattern `Ok(code) => code` to `Ok(r) => r.exitCode` |
| E2E tests | `async-runprocess-result.ks` now must capture stdout from process rather than relying on streaming; update test and expected |
| Integration tests | `runtime-stdlib.test.ts` runProcess test updated |
| Specs | `docs/specs/02-stdlib.md` — update signature and add ProcessResult description |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: update `runProcessAsync` to capture stdout+stderr into `StringBuilder`; complete future with `KOk(new KRecord(exitCode, stdout))` where `KRecord` is `{"exitCode": exitCode, "stdout": stdout}`
- [x] `stdlib/kestrel/process.ks`: add `export type ProcessResult = { exitCode: Int, stdout: String }`; update `runProcess` return type to `Task<Result<ProcessResult, ProcessError>>`
- [x] `scripts/run_tests.ks`: update `Ok(code) => code` to `Ok(r) => r.exitCode`; add `print(r.stdout)` to forward captured output
- [x] `tests/unit/async_virtual_threads.test.ks`: update `Ok(0) => 1` to `Ok(r) if r.exitCode == 0 => 1` or `Ok(r) => if r.exitCode == 0 then 1 else 0`
- [x] `tests/e2e/scenarios/positive/async-runprocess-result.ks`: update pattern; update `.expected` since stdout is now captured (no longer streamed to parent)
- [x] `tests/perf/float/run.ks`: update `Ok(v) => v` to `Ok(r) => r.exitCode`
- [x] `compiler/test/integration/runtime-stdlib.test.ts`: update inline Kestrel source to use new API; update expected stdout (process output no longer streamed)
- [x] `tests/run-e2e.sh`: check if any inline Kestrel in the script references `runProcess`
- [x] `tests/conformance/runtime/valid/task_cancel.ks`: no change needed (no Ok pattern match)
- [x] Add conformance runtime test: `tests/conformance/runtime/valid/run_process_stdout.ks`
- [x] `stdlib/kestrel/process.test.ks`: update `Ok(v) => v` to `Ok(r) => r.exitCode`
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`
- [x] `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/run_process_stdout.ks` | stdout captured; exitCode accessible; stderr also captured |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — update `runProcess` signature to `Task<Result<ProcessResult, ProcessError>>`, add `ProcessResult` type definition
- [x] `docs/specs/01-language.md` — update §5 mention of `runProcess` result type

## Build notes

- S01-18 **2026-03-07**: `KRuntime.runProcessAsync` now uses `pb.redirectErrorStream(true)` so stderr is merged into captured stdout. `KRecord` return type with `{exitCode, stdout}` requires all callers updated. `process.test.ks` was also missed in initial analysis — updated. `scripts/run_tests.ks` needed `print(r.stdout)` to forward captured subprocess output to parent process (otherwise test output would be silently discarded). `if (cond) expr` is the correct Kestrel syntax (not `if cond then expr`). All 234 compiler tests + 1011 Kestrel tests + 10 E2E tests pass.
