# Process exit code (`exit`)

## Sequence: S13-03
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/done/E13-stdlib-compiler-readiness.md)

## Summary

Expose the existing `KRuntime.exit(code)` as `exit(code: Int): Unit` in `kestrel:sys/process`. The compiler CLI must return exit code 1 on compile error; currently a Kestrel program always exits 0 unless an unhandled exception propagates.

## Current State

`KRuntime.java` already has `public static void exit(Object code)` at line 269 which calls `System.exit(c)`. However, `stdlib/kestrel/sys/process.ks` does not export this function. There is no way for Kestrel code to explicitly set the process exit code.

## Goals

1. Export `exit(code: Int): Unit` from `kestrel:sys/process` via `extern import`.
2. The function terminates the process immediately with the given exit code.
3. The type is `Unit` (not `Task<Never>`) since it's synchronous and never returns.

## Acceptance Criteria

- `exit(0)` terminates with exit code 0 (shell `$?` = 0).
- `exit(1)` terminates with exit code 1 (shell `$?` = 1).
- `exit(42)` terminates with exit code 42.
- The function is exported from `kestrel:sys/process` and importable by users.

## Spec References

- `docs/specs/02-stdlib.md` (sys/process section)

## Risks / Notes

- `exit` is synchronous and never returns. The return type `Unit` is a pragmatic choice — `Task<Never>` would require an `await` which is misleading. The compiler can note that anything after `exit(...)` is unreachable.
- No new JVM runtime code needed — just an `extern` binding to the existing `KRuntime#exit`.
- Independent of all other E13 stories.

## Tasks

- [x] `stdlib/kestrel/sys/process.ks`: add `export extern fun exit(code: Int): Unit`
- [x] `docs/specs/02-stdlib.md`: add `exit` to sys/process function table

## Build notes

`exit` is already a built-in function in Kestrel (available without imports, as used by `tests/e2e/scenarios/negative/runtime_exit_one.ks`). This story adds it to `kestrel:sys/process` so it can be explicitly imported by name. No new JVM code needed; binding to existing `KRuntime#exit(Object)` at line 269.
