# Float parsing (`parseFloat`, `toFloat`)

## Sequence: S13-07
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/done/E13-stdlib-compiler-readiness.md)

## Summary

Add `parseFloat(s: String): Option<Float>` and `toFloat(s: String): Float` to `kestrel:data/string`. The compiler lexer must parse float literals from source text; without `parseFloat`, float literal handling requires a hand-rolled parser or ugly workarounds.

## Current State

`stdlib/kestrel/data/string.ks` has `parseInt(s)` and `toInt(s)` but no float equivalents. `KRuntime.java` has `intToFloat` and `floatToInt` but no string-to-float conversion. Java's `Double.parseDouble(String)` is the natural JVM primitive.

## Goals

1. Add `KRuntime.parseFloat(Object s)` — calls `Double.parseDouble`, returns `Some(d)` or `None` on `NumberFormatException`.
2. Export `parseFloat(s: String): Option<Float>` from `kestrel:data/string`.
3. Export `toFloat(s: String): Float` from `kestrel:data/string` — returns `0.0` on bad input (same pattern as `parseInt`).
4. Handle: `"3.14"`, `"1e10"`, `"1.5E-3"`, `"-0.5"`, `"Infinity"`, `"-Infinity"`, `"NaN"`.

## Acceptance Criteria

- `parseFloat("3.14")` returns `Some(3.14)`.
- `parseFloat("1e10")` returns `Some(10000000000.0)`.
- `parseFloat("-0.5")` returns `Some(-0.5)`.
- `parseFloat("bad")` returns `None`.
- `parseFloat("")` returns `None`.
- `toFloat("2.5")` returns `2.5`; `toFloat("x")` returns `0.0`.

## Spec References

- `docs/specs/02-stdlib.md` (data/string section)

## Risks / Notes

- `Double.parseDouble` accepts `"Infinity"` and `"NaN"`. That's valid; document it.
- Independent of all other E13 stories.

## Tasks

- [x] `KRuntime.java`: add `parseFloat(Object s) → Object` (KSome/KNone) and `toFloat(Object s) → Double`
- [x] `stdlib/kestrel/data/string.ks`: add `parseFloat` and `toFloat` extern + export funs
- [x] `tests/conformance/runtime/valid/string_float_parse.ks`: conformance test
- [x] Build runtime (`cd runtime/jvm && bash build.sh`)
- [x] Compiler tests pass (`cd compiler && npm test`)
- [x] `docs/specs/02-stdlib.md`: add `parseFloat` and `toFloat` to data/string table

## Build notes

- 2025-01-01: `parseFloat` returns `Object` (KSome(Double) or KNone.INSTANCE); `toFloat` returns `Double` (boxed). Both follow the same JVM descriptor conventions as all other KRuntime extern-bound methods with complex return types.
- `Double.parseDouble` already accepts `"Infinity"`, `"-Infinity"`, `"NaN"` — no special handling needed.
- Pattern mirrors `parseInt`/`toInt` in the same module.
