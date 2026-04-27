# Self-hosted codegen: `EIs` type narrowing, `ENever`, and codegen metadata (`JvmCodegenOptions`)

## Sequence: S17-38
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-37, S17-42

## Summary

Three remaining codegen gaps:

1. **`EIs` type-narrowing**: the self-hosted codegen always emits `True`, ignoring the
   tested type. The TS reference emits `INSTANCEOF TypeClass; ... IFEQ false; pushTrue`.
2. **`ENever`**: correctly emits `null` (acceptable stub since `never` expressions are
   unreachable by construction, but should emit `ATHROW` with an assertion error in debug
   builds to catch miscompilation).
3. **`JvmCodegenOptions`**: the TS reference's `jvmCodegen` accepts an options object that
   carries imported-name resolution tables (class names, arities, var sets, etc.) built from
   the KTI codegenMeta section. The self-hosted `jvmCodegen` currently accepts no options,
   so the driver cannot pass cross-module import information to the code generator. This is
   a prerequisite for correct `EIdent` and `ECall` resolution for imported names (S17-25,
   S17-27).

## Current State

- `EIs(e, _t)`: `{ emitExpr(ctx, e); pop; pushBoolBoxed(ctx, True) }` — always `True`.
- `ENever`: `pushNull(ctx)`.
- `jvmCodegen(moduleName, prog)`: no options parameter; `CodegenContext` has no import maps.
- `codegenMeta` in the KTI format records function arities and class names but is never read
  back and passed to `jvmCodegen`.

## Relationship to other stories

- **Depends on**: S17-24..S17-27 should be done first to make the options maps useful.
- `JvmCodegenOptions` extension is a **prerequisite** for S17-25 and S17-27 to have access
  to the import metadata built from KTI codegenMeta. If those stories are implemented
  before this one, they must use placeholder empty maps and be revisited.
- **Implement early sub-slice**: the `JvmCodegenOptions` part should land with or immediately
   adjacent to the S17-25 + S17-27 execution tranche, even if the `EIs` and `ENever` parts remain
   later in the roadmap sequence.
- **Blocks**: S17-42 (E2E) for programs using `is` type narrowing or cross-module import
  resolution.

## Goals

1. **`EIs(e, t)`**: emit `e`; `INSTANCEOF <jvm class for t>`; `IFEQ falseLabel`;
   `GETSTATIC Boolean.TRUE; GOTO end; falseLabel: GETSTATIC Boolean.FALSE; end:`.
2. **`ENever`**: keep `pushNull` for now (unreachable; acceptable) but add a comment noting
   it should emit `ATHROW` with an `AssertionError` in future.
3. **`JvmCodegenOptions`**: add an `options` parameter to `jvmCodegen` carrying:
   - `importedNameToClass: Dict<String, String>` — imported fun name → JVM class.
   - `importedFunArities: Dict<String, Int>` — imported fun name → arity.
   - `importedValVarToClass: Dict<String, String>` — imported val/var → class.
   - `importedVarNames: List<String>` — imported `var` names (need unboxing).
   - `importedNameToOriginal: Dict<String, String>` — local alias → original name.
4. Update `driver.ks` to build these maps from the loaded KTI `codegenMeta` sections and
   pass them to `jvmCodegen`.

## Acceptance Criteria

- [ ] `x is String` evaluates to `True` when `x` is a String and `False` otherwise.
- [ ] `x is Int` evaluates correctly for integer values.
- [ ] After this story, S17-25 and S17-27 can use `options.importedNameToClass` to resolve
      cross-module identifiers and calls; regression tests for imported name resolution pass.
- [ ] New codegen unit tests cover `EIs` for each primitive type.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `is` type-narrowing expression
- `docs/specs/06-typesystem.md` — runtime type tests

## Risks / Notes

- The JVM class name for Kestrel's primitive types (`Int` → `java/lang/Long`, `Float` →
  `java/lang/Double`, `Bool` → `java/lang/Boolean`, `String` → `java/lang/String`, etc.)
  must match the boxing scheme used by the rest of codegen. Cross-check with TS
  `javaTypeNameToDescriptor`.
- Because this story mixes "import metadata plumb-through" with the narrower `EIs` / `ENever`
   work, it may be implemented in two commits inside one story: first the options plumbing needed
   by S17-25/S17-27, then the remaining `EIs` semantics.
