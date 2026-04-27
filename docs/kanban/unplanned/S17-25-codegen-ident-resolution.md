# Self-hosted codegen: `EIdent` — global vars, imported names, function references

## Sequence: S17-25
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24, S17-26 through S17-38, S17-42

## Summary

The self-hosted `emitExpr` for `EIdent` only loads from local parameter slots. It cannot
resolve global module-level `val`/`var` names, function references, imported names from
other modules, or nullary ADT constructors. Any identifier that does not map to a local
parameter slot silently pushes `null` instead of failing or emitting the correct bytecode.

## Current State

`codegen.ks` `loadLocal` looks up a name in `ctx.locals` (parameter slots). If found it
emits `ALOAD slot`. If not found, `emitExpr` calls `pushNull`. Missing resolution paths:

- **Global `val`/`var`**: `GETSTATIC ClassName.fieldName` (with lazy `$init` call for the
  lazy-initialization pattern).
- **Module-level `fun` references**: emit a lambda wrapper object via `emitFunctionRef`.
- **Imported val/var from another module**: `INVOKESTATIC ImportedClass.$init(); GETSTATIC
  ImportedClass.fieldName`.
- **Imported fun reference**: `INVOKESTATIC ImportedClass.$init(); emitFunctionRef(...)`.
- **Nullary ADT constructors** (`None`, `Nil`, user-defined): `GETSTATIC CtorClass.INSTANCE`.

TS reference handles all of these in the `'IdentExpr'` case (~80 lines, lines 1397–1480).

## Relationship to other stories

- **Depends on**: S17-24 (literal emission, which establishes the constant-pool helpers also
  needed here).
- **Blocks**: S17-26 (`ECall`) — function calls require being able to load a callable target,
  which depends on correct `EIdent` resolution.
- **Blocks**: S17-42 (E2E).

## Goals

1. Build a `globalNames` set (all module-level `fun`/`val`/`var` declared in the program)
   and a `globalVarNames` set (mutable globals) inside `jvmCodegen` and thread them into
   `CodegenContext`.
2. Build a `funArities` map (function name → parameter count) to enable `emitFunctionRef`.
3. Build an `importedNameToClass`, `importedFunArities`, `importedValVarToClass`,
   `importedVarNames`, and `importedNameToOriginal` map from `JvmCodegenOptions` (mirroring
   the TS reference). Extend `JvmCodegenOptions` to carry these.
4. Implement resolution priority for `EIdent` matching the TS reference order:
   a. Local parameter slot → `ALOAD`.
   b. Imported val/var → `INVOKESTATIC $init; GETSTATIC`.
   c. Imported fun → `INVOKESTATIC $init; emitFunctionRef`.
   d. `None` → `GETSTATIC KNone.INSTANCE`.
   e. `Nil`/`[]` → `GETSTATIC KNil.INSTANCE`.
   f. Nullary user ADT ctor → `GETSTATIC CtorClass.INSTANCE`.
   g. Global val/var → `GETSTATIC ClassName.fieldName` (with var unboxing).
   h. Global fun → `emitFunctionRef`.
   i. Unresolved → compile error (currently silent null).
5. Emit a compile error diagnostic for unresolved identifiers instead of pushing null.

## Acceptance Criteria

- [ ] A program that reads a module-level `val x = 42` and returns it in a function produces
      the value `42` at runtime.
- [ ] A program that passes a function by name to another function works correctly.
- [ ] `None` evaluates to the KNone singleton; a user-defined nullary ADT constructor
      evaluates to its INSTANCE.
- [ ] A program importing a `val` from another module reads the correct value.
- [ ] An unresolved identifier name produces a compile error diagnostic.
- [ ] New codegen unit tests cover each resolution path.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — identifiers and scoping
- `docs/specs/07-modules.md` — import resolution

## Risks / Notes

- The lazy `$init` method pattern for globals is required to handle circular initialization
  correctly. Mirror the TS compiler's `$init` scheme exactly to keep KTI-cached classes
  interoperable between bootstrap-compiled and self-hosted-compiled modules.
- `emitFunctionRef` needs to produce the correct lambda-wrapper object; this is also needed
  by `ECall` (S17-26). Factor into a shared helper.
