# getProcess().env full environment map

## Sequence: S12-01
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E12 Full Process Environment](../epics/done/E12-full-process-environment.md)

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

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | Add `public static KList getEnvAll()` to `KRuntime.java`: iterates `System.getenv().entrySet()`, constructs a `KRecord` per entry with fields `"0"` (key) and `"1"` (value), cons'd into a `KList` |
| Stdlib | Add `extern fun getEnvAllImpl(): List<(String, String)> = jvm("kestrel.runtime.KRuntime#getEnvAll()")` to `stdlib/kestrel/sys/process.ks` |
| Stdlib | Change `getProcess()` body: replace `env = []` with `env = getEnvAllImpl()` |
| Tests | New conformance runtime test `tests/conformance/runtime/valid/getenv_all.ks` verifying `env` is non-empty and `PATH` appears in it |
| Docs | Update `docs/specs/02-stdlib.md`: note that `getProcess().env` returns the real process environment |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `public static KList getEnvAll()` using `System.getenv().entrySet()`; each entry becomes a `KRecord` with fields `"0"` (key `String`) and `"1"` (value `String`); cons into `KList` in any order
- [x] `cd runtime/jvm && bash build.sh`
- [x] `stdlib/kestrel/sys/process.ks`: add private `extern fun getEnvAllImpl(): List<(String, String)> = jvm("kestrel.runtime.KRuntime#getEnvAll()")`
- [x] `stdlib/kestrel/sys/process.ks`: change `getProcess()` body — replace `env = []` with `env = getEnvAllImpl()`
- [x] `tests/conformance/runtime/valid/getenv_all.ks`: add conformance test
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/getenv_all.ks` | `getProcess().env` is non-empty; `PATH` appears as a `(k, v)` entry; `getEnv(k)` returns `Some(v)` for that entry |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — update the `getProcess` row to note `env` returns the actual process environment (non-empty list); remove any "always `[]`" wording

## Build notes

- 2026-04-11: Started implementation.
- 2026-04-11: `KRuntime.getEnvAll()` constructs `KRecord` tuples directly (fields `"0"` / `"1"`) using `System.getenv().entrySet()`. `Map.Entry` is available via the existing `java.util.Map` import — no new imports needed. The cast-to-`HashMap` helpers (`hashMapKeys` etc.) cannot be reused here because `System.getenv()` returns an `UnmodifiableMap`, not a `HashMap`.
- 2026-04-11: Conformance test initially had prose `// comment` lines that were picked up as expected output by the runtime conformance runner — removed prose comments, leaving only `// True` golden lines.
- 2026-04-11: 423 compiler tests pass, 1471 Kestrel tests pass.
