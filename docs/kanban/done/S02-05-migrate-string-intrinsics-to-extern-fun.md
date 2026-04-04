# Migrate `string.ks` Intrinsics to `extern fun`

## Sequence: S02-05
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Replace all ten `__string_*` compiler intrinsics used in `stdlib/kestrel/string.ks` with `extern fun` declarations bound to their underlying `KRuntime` Java static methods. Remove the corresponding hardcoded dispatch blocks from `codegen.ts` and environment bindings from `check.ts`. String operations are the highest-traffic compiler intrinsics and represent the most visible proof that the extern machinery works for production stdlib code.

## Current State

**Ten string intrinsics (all in `string.ks`):**
- `__string_length(s)` → `KRuntime.stringLength(Object): Long`
- `__string_slice(s, start, end)` → `KRuntime.stringSlice(Object,Object,Object): String`
- `__string_index_of(s, sub)` → `KRuntime.stringIndexOf(Object,Object): Long`
- `__string_equals(a, b)` → `KRuntime.stringEquals(Object,Object): Boolean`
- `__string_concat(a, b)` → `KRuntime.stringConcat(Object,Object): String`
- `__string_upper(s)` → `KRuntime.stringUpper(Object): String`
- `__string_lower(s)` → implied `KRuntime.stringLower(Object): String`
- `__string_trim(s)` → `KRuntime.stringTrim(Object): String`
- `__string_code_point_at(s, i)` → `KRuntime.stringCodePointAt(Object,Object): Long`
- `__string_char_at(s, i)` → `KRuntime.stringCharAt(Object,Object): Integer`

**Additional**: `string.ks` also uses `__char_to_string` in the private `charStr` helper. After S02-04, this should be replaced by an import or a local extern fun.

**`check.ts`**: ten `env.set('__string_*', ...)` bindings.
**`codegen.ts`**: ten `if (name === '__string_*') { ... }` blocks (lines ~1621–1688).

Note: `stack.test.ks` directly calls `__string_length` and `__string_index_of` in its test helpers. Those usages must also be replaced after this migration removes the intrinsics from the global environment.

## Relationship to other stories

- **Depends on S02-01, S02-02**: requires `extern fun` support.
- **Soft dependency on S02-04**: `string.ks` uses `__char_to_string`. If S02-04 is landed first, this migration can import from `kestrel:char` instead. If done in parallel, add a local extern fun for `charToString` in `string.ks`.
- **Independent of S02-06 through S02-10**.

## Goals

1. Replace all `__string_*` calls in `string.ks` with `extern fun` declarations. Example:
   ```kestrel
   extern fun length(s: String): Int =
     jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")
   extern fun slice(s: String, start: Int, end: Int): String =
     jvm("kestrel.runtime.KRuntime#stringSlice(java.lang.Object,java.lang.Object,java.lang.Object)")
   ```
2. All ten intrinsics removed from `codegen.ts` and `check.ts`.
3. Update `stack.test.ks`: replace `__string_length(...)` and `__string_index_of(...)` calls with `String.length(...)` and `String.indexOf(...)` module function calls.
4. Grep the entire codebase for remaining `__string_*` uses outside of `string.ks` and `stack.test.ks`; update or error if any are found.

## Acceptance Criteria

- [x] `stdlib/kestrel/string.ks` contains no `__string_*` calls.
- [x] All ten `extern fun` declarations for string operations exist in `string.ks`.
- [x] `codegen.ts` contains no `name === '__string_*'` blocks for these ten intrinsics.
- [x] `check.ts` contains no `env.set('__string_*', ...)` bindings for these ten intrinsics.
- [x] `stdlib/kestrel/stack.test.ks` does not call `__string_length` or `__string_index_of` directly.
- [x] `stdlib/kestrel/string.test.ks` passes.
- [x] `stdlib/kestrel/stack.test.ks` passes.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:string` module: API is unchanged from the user perspective.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/string.ks` | Replace 10 `__string_*` intrinsic call sites with `extern fun` declarations (or change the wrapper `fun` to `extern fun`); `charAt` and `charStr` (charStr already migrated in S02-04) private helpers converted similarly |
| `stdlib/kestrel/stack.test.ks` | Replace 7 direct `__string_length` / `__string_index_of` calls with `length(...)` / `indexOf(...)` from `kestrel:string` import |
| `compiler/src/typecheck/check.ts` | Remove 10 `env.set('__string_*', ...)` builtin bindings |
| `compiler/src/jvm-codegen/codegen.ts` | Remove 10 `if (name === '__string_*') { ... }` intrinsic dispatch blocks |

## Tasks

- [x] Convert `string.ks` top-level functions to extern fun: `length`, `slice`, `charAt`, `indexOf`, `equals`, `toUpperCase`, `trim`, `codePointAt`, `append` (→ `KRuntime#concat`), `toLowerCase`
- [x] Update `stdlib/kestrel/stack.test.ks`: add `import { length, indexOf } from "kestrel:string"` and replace 7 `__string_length`/`__string_index_of` calls  
- [x] Remove 10 `env.set('__string_*', ...)` blocks from `compiler/src/typecheck/check.ts` (and the `// String primitives` comment header)
- [x] Remove 10 `if (name === '__string_*' && ...)` dispatch blocks from `compiler/src/jvm-codegen/codegen.ts`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/string_extern_fun.ks` | Verify `length`, `slice`, `indexOf`, `equals`, `toUpperCase`, `toLowerCase`, `trim` via extern fun pathway |

## Documentation and specs to update

- [x] No spec change required — API is unchanged from user perspective. Verify `docs/specs/02-stdlib.md` kestrel:string section has no `__string_*` internal references to remove.

## Build notes

- 2026-04-04: Started implementation.
- 2026-04-04: Migrated all 10 `__string_*` intrinsic call sites in `string.ks` to `extern fun` declarations. Note: `__string_concat` maps to `KRuntime#concat` (method name without `string` prefix). `__string_char_at` maps to `KRuntime#stringCharAt`.
- 2026-04-04: Updated `stack.test.ks` to import `{ length, indexOf }` from `kestrel:string` and replaced 7 direct intrinsic calls.
- 2026-04-04: Removed 10 `env.set('__string_*', ...)` blocks from `check.ts` (including comment header).
- 2026-04-04: Removed 10 dispatch blocks from `codegen.ts`.
- 2026-04-04: All 256 compiler tests pass. `./scripts/kestrel test` exits 0.

## Risks / Notes

- **`stack.test.ks` uses intrinsics directly**: this test file (`stdlib/kestrel/stack.test.ks`) calls `__string_length` and `__string_index_of` on lines 11–35. After this migration removes those names from the global environment, the tests will fail to compile unless they are updated to use `String.length(...)` imports. The issue is minor but must not be overlooked.
- **`__string_lower` method name**: verify `KRuntime.stringLower` is the actual method name (the intrinsic is `__string_lower`; the codegen maps it). Grepping `codegen.ts` around line 1656 will confirm. If the method name diverges from the pattern, note it.
- **Correctness of `stringSlice` vs. `String.substring`**: `KRuntime.stringSlice` almost certainly implements UTF-16 code-unit slicing (not Unicode scalar value slicing). The string spec (`docs/specs/02-stdlib.md`) should clarify the behaviour. Migration does not change behaviour, but it makes the KRuntime dependency explicit.
- **Ten removals from `codegen.ts`**: modifying codegen has a history of subtle breakage. Run the full conformance suite after each batch of removals.
