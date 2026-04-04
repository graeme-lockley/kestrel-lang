# Migrate `basics.ks` Numeric, Float, and Time Intrinsics to `extern fun`

## Sequence: S02-06
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Replace the ten numeric/float/time compiler intrinsics in `stdlib/kestrel/basics.ks` with `extern fun` declarations. This covers `__int_to_float`, `__float_to_int`, seven `__float_*` math functions, and `__now_ms`. Remove the corresponding dispatch blocks from `codegen.ts` and bindings from `check.ts`.

## Current State

**Ten intrinsics in `basics.ks`:**
- `__int_to_float(n: Int): Float` → `KRuntime.intToFloat(Object): Double`
- `__float_to_int(f: Float): Int` → `KRuntime.floatToInt(Object): Long`
- `__float_floor(f: Float): Int` → `KRuntime.floatFloor(Object): Long`
- `__float_ceil(f: Float): Int` → `KRuntime.floatCeil(Object): Long`
- `__float_round(f: Float): Int` → `KRuntime.floatRound(Object): Long`
- `__float_abs(f: Float): Float` → `KRuntime.floatAbs(Object): Double`
- `__float_sqrt(f: Float): Float` → `KRuntime.floatSqrt(Object): Double`
- `__float_is_nan(f: Float): Bool` → `KRuntime.floatIsNan(Object): Boolean`
- `__float_is_infinite(f: Float): Bool` → `KRuntime.floatIsInfinite(Object): Boolean`
- `__now_ms(): Int` → `KRuntime.nowMs(): Long`

**Current `basics.ks` usage (all in functions `toFloat`, `truncate`, `floor`, `ceiling`, `round`, `abs`, `sqrt`, `isNaN`, `isInfinite`, `nowMs`):**

```kestrel
export fun toFloat(n: Int): Float      = __int_to_float(n)
export fun truncate(f: Float): Int     = __float_to_int(f)
export fun floor(f: Float): Int        = __float_floor(f)
export fun ceiling(f: Float): Int      = __float_ceil(f)
export fun round(f: Float): Int        = __float_round(f)
export fun abs(f: Float): Float        = __float_abs(f)
export fun sqrt(f: Float): Float       = __float_sqrt(f)
export fun isNaN(f: Float): Bool       = __float_is_nan(f)
export fun isInfinite(f: Float): Bool  = __float_is_infinite(f)
export fun nowMs(): Int                = __now_ms()
```

**`codegen.ts`**: ten `if (name === '__*') { ... }` blocks at lines ~1694–1778.
**`check.ts`**: ten `env.set('__*', ...)` bindings.

## Relationship to other stories

- **Depends on S02-01, S02-02**: requires `extern fun` support.
- **Independent of S02-04, S02-05, S02-07, S02-08, S02-09, S02-10**: migration stories are independent once S02-02 lands.

## Goals

1. Replace each export wrapper in `basics.ks` with a direct `extern fun`, e.g.:
   ```kestrel
   export extern fun toFloat(n: Int): Float =
     jvm("kestrel.runtime.KRuntime#intToFloat(java.lang.Object)")

   export extern fun nowMs(): Int =
     jvm("kestrel.runtime.KRuntime#nowMs()")
   ```
2. All ten intrinsics removed from `codegen.ts` and `check.ts`.
3. Grep for remaining `__int_to_float`, `__float_*`, `__now_ms` usage across the compiler and stdlib; fix any found.

## Acceptance Criteria

- [ ] `stdlib/kestrel/basics.ks` contains no `__int_to_float`, `__float_to_int`, `__float_*`, or `__now_ms` calls.
- [ ] Ten `extern fun` declarations exist in `basics.ks` covering all ten intrinsics.
- [ ] `codegen.ts` has no remaining dispatch blocks for these ten intrinsics.
- [ ] `check.ts` has no remaining `env.set` calls for these ten intrinsics.
- [ ] `stdlib/kestrel/basics.test.ks` (if it exists) passes; runtime conformance tests involving `floor`, `ceil`, `sqrt`, `isNaN` pass.
- [ ] `./scripts/kestrel test` passes.
- [ ] `cd compiler && npm test` passes.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/basics.ks` | Replace 10 wrapper `fun` bodies with `export extern fun` declarations binding `KRuntime` static methods |
| `compiler/src/typecheck/check.ts` | Remove 10 `env.set('__int_to_float'…)` / `env.set('__float_*'…)` / `env.set('__now_ms'…)` entries |
| `compiler/src/jvm-codegen/codegen.ts` | Remove 10 `if (name === '__*')` dispatch blocks for these intrinsics |
| Tests | No new tests — existing `stdlib/kestrel/basics.test.ks` exercises all 10 exported functions |
| Specs | `docs/specs/02-stdlib.md` — implementation note only; public API unchanged |

## Tasks

- [ ] Replace 10 functions in `stdlib/kestrel/basics.ks` with `export extern fun` declarations
- [ ] Remove 10 `env.set` intrinsic entries from `compiler/src/typecheck/check.ts` (lines ~261–310)
- [ ] Remove 10 `if (name === '__*')` dispatch blocks from `compiler/src/jvm-codegen/codegen.ts` (lines ~1846–1891, 1907–1911)
- [ ] Check for stray `__int_to_float`, `__float_*`, `__now_ms` references anywhere else in compiler or stdlib; remove any found
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/basics.test.ks` (existing) | Already covers all 10 exported functions — no new tests required; verify suite still passes |

## Documentation and specs to update

- [ ] `docs/specs/02-stdlib.md` — confirm `kestrel:basics` section is accurate (no API change; implementation note not required)

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:basics` module: no API change.

## Risks / Notes

- **`nowMs()` temporal coupling**: `__now_ms` is in `basics.ks` rather than `process.ks`. This is an existing organizational inconsistency. Migrating it as-is preserves the inconsistency. Do not reorganize during this story — keep the same module structure.
- **Return type coercions**: the existing codegen emits each as a static call returning a boxed Java type matching the Kestrel type. When `extern fun` emits the same `INVOKESTATIC`, the return value on the JVM stack is already a `Long`, `Double`, or `Boolean` — no further boxing needed. Confirm this for each intrinsic to avoid double-boxing.
- **`KRuntime.floatFloor` vs `Math.floor`**: the runtime helpers exist because Kestrel's `Int` is `Long` and Java's `Math.floor` returns `double`. The helpers bridge this gap. Using the `KRuntime` static methods in extern bindings keeps this delegation pattern.
