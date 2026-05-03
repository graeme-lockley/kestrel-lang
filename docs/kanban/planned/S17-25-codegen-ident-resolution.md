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

Recent pipeline work added a temporary self-hosted `main(String[])` shim so compiled modules
can be launched while real entrypoint and global-init codegen is still pending. That shim is
enough to make `./kestrel test` and `./scripts/test-all.sh` runnable, but it does not make
identifier resolution correct: unresolved globals still become `null`, imported globals still
skip `$init`, and runtime-sensitive E2E coverage is currently gated behind
`E2E_SKIP_PENDING_CODEGEN` markers until this story and S17-37 land together.

## Relationship to other stories

- **Depends on**: S17-24 (literal emission, which establishes the constant-pool helpers also
  needed here).
- **Implement alongside**: S17-37. Real identifier resolution and real module startup need to
  ship together so the temporary `main` shim and the temporary E2E skips can be removed in one
  tranche.
- **Blocks**: S17-26 (`ECall`) — function calls require being able to load a callable target,
  which depends on correct `EIdent` resolution.
- **Blocks**: S17-37 (`$init` must be callable from imported/global reads in the same delivery
  slice).
- **Blocks**: S17-42 (E2E / no-Node validation).

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
6. Replace the current silent-null fallback paths that only exist to keep the temporary
  self-hosted launcher alive; after this story the runtime should see real values or a real
  compile diagnostic, never placeholder `null`.

## Acceptance Criteria

- [ ] A program that reads a module-level `val x = 42` and returns it in a function produces
      the value `42` at runtime.
- [ ] A program that passes a function by name to another function works correctly.
- [ ] `None` evaluates to the KNone singleton; a user-defined nullary ADT constructor
      evaluates to its INSTANCE.
- [ ] A program importing a `val` from another module reads the correct value.
- [ ] An unresolved identifier name produces a compile error diagnostic.
- [ ] The temporary execution path no longer relies on `pushNull` for unresolved identifiers in
  any identifier-resolution branch used by module startup.
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
- Do not remove the temporary `main` shim until S17-37 is ready in the same tranche; otherwise
  `./kestrel test` regresses from "runtime-sensitive tests skipped" back to "compiled module is
  not executable at all".

## Impact analysis

| Area | Change | Risk |
|------|--------|------|
| `stdlib/kestrel/tools/compiler/codegen.ks` | Add `type JvmCodegenOptions` record; add `type ModuleContext` record; extend `jvmCodegen` signature to accept `ModuleContext`; add `emitFunctionRef` and `emitVarUnbox` helpers; replace single-line `EIdent` stub with full 9-step resolution chain; add `INSTANCE` field emission for nullary ADT constructors in `emitCtorClass`. | Medium — touches central `jvmCodegen` entry point and `emitCtorClass`; must not regress existing `emitVal`/`emitVar`/`emitFunDecl`/`emitExternFun` paths. |
| `stdlib/kestrel/tools/compiler/kti.ks` | Fix `extractCodegenMeta` to classify symbols correctly (actual `funArities` from parsed `TDFun`/`TDExternFun`, `varNames` from `TDVar`, `valOrVarNames` from `TDVal`/`TDVar`, `adtConstructors` per ADT type, `exceptionDecls` from `TDException`). Extend `DepBindingBundle` with codegen import maps (`importedNameToClass`, `importedFunArities`, `importedValVarToClass`, `importedVarNames`, `importedNameToOriginal`). Update `loadDepBindings` to accept class-name triples `(spec, ktiPath, className)` and populate codegen fields from `depKti.codegenMeta`. | Medium — changes to `DepBindingBundle` and `loadDepBindings` signature; `driver.ks` caller must be updated in the same commit. |
| `stdlib/kestrel/tools/compiler/driver.ks` | Update `doTypecheckAndEmit` to build a `ModuleContext` from `depBindings` codegen maps and pass it to `jvmCodegen`; update `loadDepBindings` call-site to pass `(spec, ktiPath, className)` triples (class name derived from same `classNameForPath` helper). | Low — straightforward plumbing change; existing types guide the update. |
| `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Add test groups covering global `val`/`var` reads, function-reference emission, nullary ADT constructor resolution, and unresolved-identifier diagnostic. | Low — test-only additions. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add test group covering `EIdent` resolution paths: local slot (existing), global val, global fun, `None`, `Nil`, user ADT ctor, imported val, imported fun. | Low — test-only additions. |
| `docs/specs/01-language.md` | No change required — identifier scoping is already documented. | None |
| `docs/specs/07-modules.md` | No change required — import resolution is already documented at the KTI level. | None |

**Compatibility notes**: `jvmCodegen` gains a required second parameter (`ModuleContext`). All callers (currently only `driver.ks` and test files) must be updated. The lazy `$init` pattern for imported names mirrors the TS reference exactly, ensuring KTI-cached classes produced by the bootstrap compiler remain interoperable with self-hosted compiled modules.

**Rollback**: revert is clean — only `codegen.ks`, `kti.ks`, `driver.ks`, and test files are touched.

## Tasks

- [ ] In `codegen.ks`: define `type JvmCodegenOptions` record with fields `importedValVarToClass: Dict<String, String>`, `importedVarNames: Dict<String, Unit>`, `importedFunArities: Dict<String, Int>`, `importedNameToClass: Dict<String, String>`, `importedNameToOriginal: Dict<String, String>`, and `importedAdtClasses: Dict<String, (String, Int)>`.
- [ ] In `codegen.ks`: define `type ModuleContext` record with fields `className: String`, `globalNames: Dict<String, Unit>`, `globalVarNames: Dict<String, Unit>`, `funArities: Dict<String, Int>`, `adtClassByConstructor: Dict<String, String>`, `adtConstructorArity: Dict<String, Int>`, and `options: JvmCodegenOptions`.
- [ ] In `codegen.ks`: add `fun emitFunctionRef(ctx: CodegenContext, mctx: ModuleContext, ownerClass: String, methodName: String, arity: Int): Unit` that emits `LDC_W class(ownerClass)`, `LDC_W string(methodName)`, `LDC_W int(arity)`, `INVOKESTATIC KFunctionRef.of(Class,String,Int)`.
- [ ] In `codegen.ks`: add `fun emitVarUnbox(ctx: CodegenContext): Unit` that emits `CHECKCAST KRecord`, `LDC_W "0"`, `INVOKEVIRTUAL KRecord.get`.
- [ ] In `codegen.ks`: add `fun emitInitCall(ctx: CodegenContext, targetClass: String): Unit` that emits `INVOKESTATIC targetClass.$init()V`.
- [ ] In `codegen.ks`: update `emitCtorClass` to add a `static final INSTANCE` field and a `<clinit>` that `NEW`, `DUP`, `INVOKESPECIAL <init>`, `PUTSTATIC` only when the constructor arity is zero (i.e., it's a nullary ADT ctor).
- [ ] In `codegen.ks`: replace the single-line `EIdent` arm of `emitExpr` with the full 9-step resolution chain mirroring the TS reference order: (a) local slot → `ALOAD` + optional `emitVarUnbox`; (b) global val/var → `GETSTATIC` + optional `emitVarUnbox`; (c) global fun → `emitFunctionRef`; (d) imported val/var → `emitInitCall` + `GETSTATIC` + optional `emitVarUnbox`; (e) imported fun → `emitInitCall` + `emitFunctionRef`; (f) `None` → `GETSTATIC KNone.INSTANCE`; (g) `Nil`/`[]` → `GETSTATIC KNil.INSTANCE`; (h) nullary user ADT ctor → `GETSTATIC CtorClass.INSTANCE`; (i) unresolved → emit a compile error diagnostic (do not call `pushNull`).
- [ ] In `codegen.ks`: add `fun buildModuleContext(moduleName: String, prog: Ast.Program, options: JvmCodegenOptions): ModuleContext` that scans `prog.body` to populate `globalNames`, `globalVarNames`, `funArities`, `adtClassByConstructor`, and `adtConstructorArity`.
- [ ] In `codegen.ks`: update `jvmCodegen` to accept `mctx: ModuleContext` as a second parameter (replacing the inline `moduleName` string) and thread `mctx` through `emitDecl` and `emitExpr` so the resolution maps are available.
- [ ] In `kti.ks`: fix `extractCodegenMeta` to properly scan `prog.body`: collect `funArities` from `TDFun`/`TDExternFun` arity; `asyncFunNames` from `TDFun` async flag; `varNames` from `TDVar`; `valOrVarNames` from `TDVal`/`TDVar`; `adtConstructors` from `TDType` bodies; `exceptionDecls` from `TDException`. Respect `TDExport(EIDecl(...))` wrappers.
- [ ] In `kti.ks`: extend `DepBindingBundle` with codegen fields: `importedNameToClass: Dict<String, String>`, `importedFunArities: Dict<String, Int>`, `importedValVarToClass: Dict<String, String>`, `importedVarNames: Dict<String, Unit>`, `importedNameToOriginal: Dict<String, String>`.
- [ ] In `kti.ks`: update `emptyDepBundle` to initialise the new codegen fields to empty dicts.
- [ ] In `kti.ks`: update `loadDepBindings` to accept a class-name triple `(spec, ktiPath, className)` (third element is the JVM internal class name for the dependency). For each `IDNamed` import that matches the current dep, use `depKti.codegenMeta` to populate `importedNameToClass`, `importedFunArities`, `importedValVarToClass`, `importedVarNames`, `importedNameToOriginal` using the resolved `className`. For `IDNamespace` imports populate namespace entries accordingly (deferred to S17-26/S17-27; an empty/pass-through is acceptable here).
- [ ] In `driver.ks`: update the `doTypecheckAndEmit` call-site for `loadDepBindings` to pass `(dep.spec, ktiPath, classNameForPath(canonicalPath(dep.path)))` triples instead of pairs.
- [ ] In `driver.ks`: after `DepLoadOk(depBindings)`, build a `Codegen.JvmCodegenOptions` from `depBindings` codegen fields and construct a `Codegen.ModuleContext` via `buildModuleContext(moduleName, prog, codegenOptions)`, then pass `mctx` to `Codegen.jvmCodegen`.
- [ ] Run `cd compiler && npm test`.
- [ ] Run `./scripts/kestrel test`.

## Tests to add

| Layer | File | What the test asserts |
|-------|------|-----------------------|
| Unit — codegen-decl | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Module with `val x = 42` compiles; class bytes are non-empty. |
| Unit — codegen-decl | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Module with `var y = 1` compiles; class bytes are non-empty (var field + mutable unboxing path). |
| Unit — codegen-decl | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Module with `fun f(x: Int): Int = x; fun g(): Int = f` compiles (fun-reference path). |
| Unit — codegen-decl | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Module with `type Color = Red \| Green` produces class bytes for `CtorClass` inner classes that contain an `INSTANCE` field (nullary GETSTATIC path); verified by checking `Dict.size(result.classes) >= 3`. |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent` for a bound local slot emits `ALOAD` (existing coverage; verify still passes). |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent("None")` emits `GETSTATIC` referencing `KNone` class bytes. |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent("Nil")` emits `GETSTATIC` referencing `KNil`. |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent("x")` where `x` is in `mctx.globalNames` emits `GETSTATIC ClassName.x`. |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent("f")` where `f` is in `mctx.funArities` emits `INVOKESTATIC KFunctionRef.of`. |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent("imported_val")` where it appears in `options.importedValVarToClass` emits `INVOKESTATIC $init` then `GETSTATIC`. |
| Unit — codegen-expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EIdent("imported_fun")` where it appears in `options.importedNameToClass` + `options.importedFunArities` emits `INVOKESTATIC $init` then `INVOKESTATIC KFunctionRef.of`. |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — No textual change needed; identifier scoping is already documented correctly. Verify the section on name resolution order still accurately describes global → local priority.
- [ ] `docs/specs/07-modules.md` — No textual change needed; the `$init` lazy-initialisation contract is already noted. Verify that the KTI `codegenMeta` fields (`funArities`, `varNames`, etc.) described there match the fields now correctly populated by `extractCodegenMeta`.
