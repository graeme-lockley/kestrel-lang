# `extern import` — Sidecar File Must Reflect User Overrides

## Sequence: S02-15
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01 through S02-14, S02-16, S02-17, S02-18

## Summary

When an `extern import` declaration includes an override block, the generated `<Alias>.extern.ks` sidecar file ignores those overrides and always shows the auto-generated (potentially incorrect) signatures. This misleads any developer reading the sidecar to understand an API — they see wrong types (e.g. `_T0` instead of the correct `SB` return type for `append`). The sidecar is intended as the canonical reference for how a Java class is bound, so it must faithfully reflect what the compiler actually uses.

## Current State

In `compiler/src/compile-file-jvm.ts`, `expandExternImports` creates a `stringOverrideMap` that is always **empty**, then calls `generateStubs(meta, alias, stringOverrideMap)` for sidecar generation — bypassing all user overrides:

```ts
const stringOverrideMap = new Map<...>();
// (sidecar always uses auto-generated types — no overrides shown)
const stubs = generateStubs(meta, alias, stringOverrideMap);
```

The AST-level overrides (`overrideMap`) are applied correctly when generating `ExternFunDecl` nodes (the compiler uses the right types). The error is purely in the sidecar rendering path.

## Relationship to other stories

- **Depends on S02-13**: sidecar emission was introduced there.
- **Independent of S02-14**: this is a documentation-correctness fix, not a codegen fix.

## Goals

1. The `<Alias>.extern.ks` sidecar file reflects the **effective** signature of every method — either the auto-generated signature or the user override, whichever the compiler uses.
2. Methods that were not overridden continue to show their auto-generated signatures unchanged.
3. If a method was overridden, the sidecar shows the overridden signature (the same params and return type that the compiled code uses), not the auto-generated one.
4. The sidecar retains its header comment noting that it is auto-generated; a secondary note is added indicating any overrides present.

## Acceptance Criteria

- [ ] Given `extern import "java:java.lang.StringBuilder" as SB { fun append(instance: SB, p0: String): SB }`, the generated `SB.extern.ks` sidecar shows `extern fun append(instance: SB, p0: String): SB` (not the auto-generated `_T0` variant).
- [ ] Methods **not** in the override block are still shown with their auto-generated signatures in the sidecar.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/compile-file-jvm.ts` | `expandExternImports`: add `typeToString` helper; build `stringOverrideMap` from `overrideMap` by looking up each override's method in `meta` to determine if receiver should be stripped from params |
| `compiler/test/integration/extern-import.test.ts` | Add test confirming override appears in sidecar with correct signature |
| `docs/specs/01-language.md` | Note that sidecar reflects effective (overridden) signatures |

## Tasks

- [x] Add `typeToString(t: Type): string` helper in `compile-file-jvm.ts` to convert AST Type → Kestrel source string
- [x] Populate `stringOverrideMap` from `overrideMap` before calling `generateStubs`: for each override, look up the method in `meta.methods` to determine if it's an instance method; if so, skip the first param (receiver) when building `kestrelParams`; convert all types with `typeToString`
- [x] Add integration test: `extern import "java:java.lang.StringBuilder" as SB { fun append(instance: SB, p0: String): SB }` → sidecar shows `extern fun append(instance: SB, p0: String): SB`, not auto-generated form
- [x] Update `docs/specs/01-language.md` — note sidecar reflects overridden signatures
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/extern-import.test.ts` | Sidecar for `extern import` with override block shows the override signature for overridden methods and auto-generated for others |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — `extern import` description: add note that sidecar reflects effective (overridden) signatures

## Build notes

- 2026-04-04: Added `typeToString` helper in `compile-file-jvm.ts` to convert AST `Type` nodes to Kestrel source strings. Handles `PrimType`, `IdentType`, `QualifiedType`, `AppType`, `ArrowType`, `TupleType`, `UnionType`; falls back to `'Any'` for complex/unsupported types.
- 2026-04-04: Populated `stringOverrideMap` from `overrideMap` before `generateStubs` call. Instance methods: drop first param (receiver) since `generateStubs` adds it via `receiverType`. Method lookup uses `jvmMethodName` or `new${alias}` for constructors to determine isInstance.
- 2026-04-04: All 314 compiler tests pass.

## Spec References

- `docs/specs/01-language.md` — `extern import` description; note that the sidecar reflects effective (overridden) signatures.

## Risks / Notes

- The fix is small: pass the actual string-form overrides to `generateStubs` for sidecar generation. The override map used for AST generation (`overrideMap`, keyed on `kestrelName`) must be converted to the string form expected by `generateStubs`. Verify the key format matches between the two maps to avoid silent misses.
- The `stringOverrideMap` for the sidecar path needs to be built in the same name-resolution order as the AST path (constructors sorted by param count, then non-constructors in declaration order) or the wrong override may be shown for an overloaded method.
