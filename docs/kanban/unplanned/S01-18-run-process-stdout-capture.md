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
