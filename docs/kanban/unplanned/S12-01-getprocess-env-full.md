# getProcess().env full environment map

## Sequence: S12-01
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E12 Full Process Environment](../epics/unplanned/E12-full-process-environment.md)

## Summary

`getProcess().env` is spec'd as `List<(String, String)>` but always returns `[]`. This story makes it return the real process environment by adding a `KRuntime.getEnvAll()` static method that converts `System.getenv().entrySet()` into a `KList` of `KRecord` tuples, then calling it from `getProcess()`.

## Current State

`stdlib/kestrel/sys/process.ks` hardcodes `env = []` in `getProcess()`. `KRuntime.java` has no `getEnvAll` method. The `getEnv(String)` single-variable lookup (added in S11-01) already works correctly.

## Relationship to other stories

- Requires S11-01 (done) — `getEnv(String)` proved the KRuntime pattern.
- No dependency on other E12 stories (this is the only story).

## Goals

1. `getProcess().env` returns the full `List<(String, String)>` at runtime.
2. Result is consistent with `getEnv(name)`: every `(k, v)` pair in `env` satisfies `getEnv(k) == Some(v)`.

## Acceptance Criteria

- `getProcess().env` is non-empty for any normal process invocation.
- `PATH` (or a known-set variable) appears in `getProcess().env`.
- The result is consistent with `getEnv`: for a sampled entry `(k, v)` from `env`, `getEnv(k)` returns `Some(v)`.
- A conformance runtime test exercises all three points.
- `docs/specs/02-stdlib.md` `getProcess` row is updated to document the populated `env` field.

## Spec References

- `docs/specs/02-stdlib.md` (sys/process section, `getProcess` row)

## Risks / Notes

- Tuples at the JVM level are `KRecord` objects (fields `"0"` and `"1"`). `KRuntime.getEnvAll()` must construct `KRecord` instances directly — the existing `hashMapKeys()`/`hashMapValues()` helpers cast to `HashMap` and cannot be used on the `UnmodifiableMap` returned by `System.getenv()`.
- Order of `System.getenv().entrySet()` is undefined; the test must not assert ordering.
