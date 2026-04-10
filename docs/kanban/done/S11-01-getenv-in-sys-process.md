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

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | Add `KRuntime.getEnv(Object)` static method returning `KSome(value)` or `KNone.INSTANCE` |
| Stdlib | Add `extern fun getEnv(name: String): Option<String>` + export in `stdlib/kestrel/sys/process.ks` |
| Tests | New conformance runtime test `tests/conformance/runtime/valid/getenv.ks` |
| Docs | Add `getEnv` to `docs/specs/02-stdlib.md` sys/process section |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `public static Object getEnv(Object name)` using `System.getenv()`
- [x] `stdlib/kestrel/sys/process.ks`: add `extern fun getEnv(name: String): Option<String> = jvm("kestrel.runtime.KRuntime#getEnv(java.lang.Object)")` and export it
- [x] `tests/conformance/runtime/valid/getenv.ks`: conformance test for `Some` and `None` cases
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/getenv.ks` | `getEnv("PATH")` returns `Some(…)` non-empty; `getEnv("KESTREL_DOES_NOT_EXIST_XYZ")` returns `None` |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `getEnv(name: String): Option<String>` to the sys/process section

## Build notes

- 2026-04-10: Started implementation.
- 2026-04-10: Used `export extern fun getEnv` directly (same pattern as `export extern fun` in char.ks/string.ks) rather than a private extern + wrapper, since the function needs no transformation of its return value. KRuntime returns `KSome(value)` or `KNone.INSTANCE` which the Kestrel runtime handles correctly for `Option<String>`.
