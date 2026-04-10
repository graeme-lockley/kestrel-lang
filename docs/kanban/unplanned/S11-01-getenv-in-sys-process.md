# getEnv in kestrel:sys/process

## Sequence: S11-01
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E11 Pure-Kestrel Test Runner](../epics/unplanned/E11-pure-kestrel-test-runner.md)

## Summary

Expose environment variables to Kestrel programs via `getEnv(name: String): Option<String>` in `kestrel:sys/process`. The current `getProcess()` function returns `env = []` always; this story adds a working single-variable lookup backed by the JVM `System.getenv()` API.

## Current State

`stdlib/kestrel/sys/process.ks` exports `getProcess()` which returns a record with `env = []` (hardcoded empty list). There is no way for a Kestrel program to read an environment variable. `KRuntime.java` has no `getEnv` method.

## Relationship to other stories

- Required by **S11-03** (test-runner reads `KESTREL_BIN` from the environment).
- No dependency on S11-02.

## Goals

1. Kestrel programs can call `getEnv("VAR")` and receive `Some(value)` or `None`.
2. The implementation is backed by `KRuntime.getEnv(String)` using `System.getenv()`.

## Acceptance Criteria

- `getEnv("PATH")` returns `Some(…)` when `PATH` is set in the environment.
- `getEnv("KESTREL_BIN_DOES_NOT_EXIST")` returns `None`.
- A conformance runtime test exercises both cases.

## Spec References

- `docs/specs/02-stdlib.md` (sys/process section)

## Risks / Notes

- Keep `getProcess().env` as `[]` for now — adding full env map is a larger change outside this epic's scope.
