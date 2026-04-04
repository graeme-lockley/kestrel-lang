# Migrate `char.ks` Intrinsics to `extern fun`

## Sequence: S02-04
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Replace the three `__char_*` compiler intrinsics in `stdlib/kestrel/char.ks` with `extern fun` declarations bound to their underlying Java runtime methods. Remove the corresponding hardcoded dispatch blocks from `compiler/src/jvm-codegen/codegen.ts` and the environment bindings from `compiler/src/typecheck/check.ts`. After this story, `char.ks` is the first stdlib file to be free of compiler-intrinsic coupling.

## Current State

**Three intrinsics in `char.ks`:**
- `__char_code_point(c: Char): Int` → codegen emits `INVOKESTATIC KRuntime.charCodePoint(Object): Long`
- `__char_from_code(n: Int): Char` → codegen emits `INVOKESTATIC KRuntime.charFromCode(Object): Integer`
- `__char_to_string(c: Char): String` → codegen emits `INVOKESTATIC KRuntime.charToString(Object): String`

**Current `char.ks` usage:**
```kestrel
export fun codePoint(c: Char): Int  = __char_code_point(c)
export fun fromCode(n: Int): Char   = __char_from_code(n)
export fun charToString(c: Char): String = __char_to_string(c)
```

**Note**: `__char_to_string` is also used as a local helper inside `stdlib/kestrel/string.ks` (`fun charStr(c: Char): String = __char_to_string(c)`). The migration of `string.ks` (S02-05) must update or replace that usage.

**`check.ts`**: all three are registered in the typecheck environment with hardcoded `env.set('__char_*', generalize(...))` calls.

**`codegen.ts`**: three `if (name === '__char_*') { ... }` blocks (lines ~1675–1697).

## Relationship to other stories

- **Depends on S02-01, S02-02**: requires `extern fun` to be fully supported in parser, typecheck, and codegen.
- **Soft dependency for S02-05** (string.ks): `string.ks` uses `__char_to_string` in a private helper. S02-05 must either: (a) convert that helper to use an import from `kestrel:char`, or (b) declare its own local `extern fun charToString`. Coordinate.
- **Independent of S02-06 through S02-10**: migration stories are independent of each other.

## Goals

1. Replace each `export fun` wrapper in `char.ks` with a direct `extern fun` declaration:
   ```kestrel
   export extern fun codePoint(c: Char): Int =
     jvm("kestrel.runtime.KRuntime#charCodePoint(java.lang.Object)")

   export extern fun fromCode(n: Int): Char =
     jvm("kestrel.runtime.KRuntime#charFromCode(java.lang.Object)")

   export extern fun charToString(c: Char): String =
     jvm("kestrel.runtime.KRuntime#charToString(java.lang.Object)")
   ```
2. Remove the three `if (name === '__char_*') { ... }` blocks from `codegen.ts`.
3. Remove the three `env.set('__char_*', ...)` bindings from `check.ts`.
4. Verify nothing else in the compiler or stdlib references `__char_code_point`, `__char_from_code`, or `__char_to_string` (grep to confirm).
5. Update `string.ks` to remove its direct use of `__char_to_string` (coordinate with S02-05, or handle here as a prerequisite patch).

## Acceptance Criteria

- [x] `stdlib/kestrel/char.ks` contains no `__char_*` calls.
- [x] `char.ks` exports `codePoint`, `fromCode`, `charToString` as `extern fun` declarations.
- [x] `codegen.ts` contains no `name === '__char_*'` blocks for `charCodePoint`, `charFromCode`, `charToString`.
- [x] `check.ts` contains no `env.set('__char_code_point', ...)`, `env.set('__char_from_code', ...)`, `env.set('__char_to_string', ...)`.
- [x] `stdlib/kestrel/char.test.ks` passes.
- [x] `stdlib/kestrel/string.ks` no longer calls `__char_to_string` directly (updated to call `Char.charToString` or equivalent).
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:char` module: verify API documentation reflects the change from wrappers to extern funs (API is unchanged from the user perspective).

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/char.ks` | Replace three `export fun` wrappers with `export extern fun` declarations bound to `KRuntime#charCodePoint`, `#charFromCode`, `#charToString` |
| `stdlib/kestrel/string.ks` | Replace private `fun charStr` (calls `__char_to_string` intrinsic) with a local `extern fun charStr` declaration |
| `compiler/src/typecheck/check.ts` | Remove three `env.set('__char_code_point', ...)`, `env.set('__char_to_string', ...)`, `env.set('__char_from_code', ...)` builtin bindings |
| `compiler/src/jvm-codegen/codegen.ts` | Remove three `if (name === '__char_*') { ... }` intrinsic dispatch blocks |
| `docs/specs/02-stdlib.md` | Minor description update to remove "VM primitive `__char_*`" references in the `kestrel:char` table |

## Tasks

- [x] Update `stdlib/kestrel/char.ks`: replace `export fun codePoint`, `fromCode`, `charToString` with `export extern fun` declarations using `jvm("kestrel.runtime.KRuntime#...")` descriptors
- [x] Update `stdlib/kestrel/string.ks`: change `fun charStr(c: Char): String = __char_to_string(c)` to `extern fun charStr(c: Char): String = jvm("kestrel.runtime.KRuntime#charToString(java.lang.Object)")`
- [x] Remove `env.set('__char_code_point', ...)` from `compiler/src/typecheck/check.ts`
- [x] Remove `env.set('__char_to_string', ...)` from `compiler/src/typecheck/check.ts`
- [x] Remove `env.set('__char_from_code', ...)` from `compiler/src/typecheck/check.ts`
- [x] Remove `if (name === '__char_code_point' && ...)` block from `compiler/src/jvm-codegen/codegen.ts`
- [x] Remove `if (name === '__char_to_string' && ...)` block from `compiler/src/jvm-codegen/codegen.ts`
- [x] Remove `if (name === '__char_from_code' && ...)` block from `compiler/src/jvm-codegen/codegen.ts`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/char_extern_fun.ks` | Verify `codePoint`, `fromCode`, `charToString` all produce correct values via the extern fun pathway |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md`: remove `(VM primitive __char_code_point)` and `(primitive __char_from_code)` parenthetical notes from the `kestrel:char` API table

## Build notes

- 2026-04-04: Started implementation.
- 2026-04-04: Replaced all three `__char_*` wrapper funs in `char.ks` with `export extern fun` declarations. `string.ks` `charStr` private helper replaced with a local `extern fun` pointing to the same `KRuntime#charToString` binding — avoids a new module import dependency.
- 2026-04-04: First test run failed on conformance fixture — import syntax `import kestrel:char as Char` is not valid; correct form is `import { ... } from "kestrel:char"`.
- 2026-04-04: Second test run failed — leading `//` comment was picked up as expected output by `extractExpectedStdoutLines`; prefixed with "Runtime conformance:" which matches the doc-only exclusion pattern.
- 2026-04-04: All 255 compiler tests and 1014 Kestrel tests pass.

## Risks / Notes

- **KRuntime method names are stable**: `KRuntime.charCodePoint`, `KRuntime.charFromCode`, `KRuntime.charToString` are the actual method names. If the runtime ever renames these, the `extern fun` binding must be updated as well. This is a necessary trade-off versus intrinsics where the codegen absorbs any renaming internally.
- **`string.ks` coupling**: the `__char_to_string` usage in `string.ks` is in a `fun` (not `export fun`), so it is private to the module. Removing it requires either importing from `kestrel:char` (adding a module dependency) or declaring a local internal `extern fun`. The import approach is cleaner architecturally and makes the inter-module relationship explicit.
- **Test coverage of char.ks**: `char.test.ks` exercises `codePoint`, `fromCode`, `charToString`. Run this directly against the JVM backend after the migration to validate bytecode correctness.
