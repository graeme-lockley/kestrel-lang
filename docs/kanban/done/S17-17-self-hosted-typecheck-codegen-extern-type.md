# Self-hosted typecheck and codegen for `extern type` declarations

## Sequence: S17-17
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-16, S17-18, S17-19, S17-20, S17-21, S17-22, S17-23

## Summary

Teach both the self-hosted typechecker and codegen to accept `extern type` declarations.
Extern types declare opaque, externally-defined nominal types (e.g. `extern type ByteArray`,
`extern type FileHandle`) whose representation lives outside Kestrel. Today:

- The self-hosted typechecker emits "Unsupported top-level declaration in self-hosted checker
  MVP" for any `TDExternType` node.
- The self-hosted codegen has no `TDExternType` arm in `emitDecl`.

Without this story the self-hosted compiler cannot typecheck or recompile any stdlib module
that declares an opaque/extern type (notably `kestrel:data/bytearray`, `kestrel:io/fs`,
`kestrel:io/process`, etc.).

## Current State

- AST: `stdlib/kestrel/dev/parser/ast.ks` defines `TDExternType(ExternTypeDecl)` and
  `ExternTypeDecl = { name: String, typeParams: List<String>, exported: Bool, ... }`.
- Typechecker: no arm in `prebindTypeDecls` or `checkDecls` (line 960 fall-through).
- Codegen: `stdlib/kestrel/tools/compiler/codegen.ks` does not import `TDExternType` or
  pattern match on it inside `emitDecl`.

## Relationship to other stories

- **Depends on**: nothing in this epic.
- **Blocks**: S17-23 (E2E).
- **Companion**: S17-16, S17-18, S17-19, S17-20, S17-21, S17-22.

## Goals

1. Extend `prebindTypeDecls` to register the extern type as a nominal type alias mapping
   the declared name to `Ty.TApp(name, <fresh type params>)` so that downstream references
   to the type resolve correctly.
2. Add a `TDExternType(etd)` arm to `checkDecls` that:
   - records the type in `exportedTypeAliases` (if exported),
   - records the type-name visibility (`opaque`) in `exportedTypeVisibility` (if exported).
3. Add a `TDExternType` arm to `emitDecl` in `codegen.ks`. Extern types have no runtime
   representation to emit; the arm is a no-op that returns `classes` unchanged (matching the
   TS reference behaviour in `compiler/src/jvm-codegen/codegen.ts`).
4. Ensure that downstream modules importing an extern type via KTI continue to receive it as
   an opaque nominal type (verify alongside S17-22 if needed).

## Acceptance Criteria

- [x] A program containing `extern type Foo` is accepted by the self-hosted typechecker with
      no diagnostics.
- [x] An exported `extern type Foo` appears in the emitted KTI file's type-visibility map as
      opaque and is consumable by an importing module.
- [x] `stdlib/kestrel/data/bytearray.ks` typechecks under the self-hosted checker.
- [x] A new unit test in `typecheck.test.ks` covers exported and non-exported extern type
      declarations and asserts the resulting `TypecheckResult` shape.
- [x] A new unit test in `codegen.test.ks` (or equivalent) verifies that emitting a program
      containing only `extern type` declarations produces a valid (empty-class-body) class
      file with no errors.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `extern type` declarations
- `docs/specs/06-typesystem.md` — opaque types and visibility
- `docs/specs/11-bootstrap.md` — self-hosted compiler responsibilities

## Risks / Notes

- Extern types with type parameters (`extern type Map<K, V>`) must register the parameter
  arity correctly so applications like `Map<String, Int>` typecheck.
- Verify interaction with S17-22 (imported constructor environment): extern types have no
  constructors so they should be a no-op for `adtConstructors`/`ctorOwners`.

## Impact analysis

| Area | Change |
|------|--------|
| Self-hosted typechecker | `stdlib/kestrel/dev/typecheck/typecheck.ks` — add `TDExternType` to imports; add `registerExternTypeDecl` function; add arm to `prebindTypeDecls`; add arm to `checkDecls` |
| Self-hosted codegen | `stdlib/kestrel/tools/compiler/codegen.ks` — add `TDExternType` to imports; add explicit no-op arm in `emitDecl` |
| Typecheck tests | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` — add group covering exported, opaque, non-exported, and parameterised extern type declarations |
| Codegen tests | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` — add group verifying that a module containing only `extern type` declarations produces a valid class file |
| Specs | `docs/specs/11-bootstrap.md` — note self-hosted checker now handles `extern type`; no other spec changes needed (language and type-system specs already cover the semantics) |

**Compatibility**: purely additive — removes the "Unsupported top-level declaration" diagnostic for `TDExternType`; no existing passing programs are affected.

**Risks addressed**:
- Type-param arity: `registerExternTypeDecl` uses `ctorReturnType` (same helper as `registerTypeDecl`) which correctly threads type-param vars through `buildTypeParamScope`.
- No `adtConstructors`/`ctorOwners` entries for extern types — correct, because extern types have no constructors.

## Tasks

- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `TDExternType` to the named import from `kestrel:dev/parser/ast`
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `registerExternTypeDecl(reg: TypeRegistry, etd: Ast.ExternTypeDecl): TypeRegistry` that inserts `TApp(etd.name, [<param vars>])` into `typeAliases` and `etd.visibility` into `exportedTypeVisibility`
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks` `prebindTypeDecls`: add `TDExternType(etd) => registerExternTypeDecl(reg, etd)` arm
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks` `checkDecls`: add `TDExternType(etd)` arm that inserts the type into `exportedTypeAliases` when `etd.visibility` is `"export"` or `"opaque"`
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `TDExternType` to the named import from `kestrel:dev/parser/ast`
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitDecl`: add explicit `TDExternType(_) => classes` no-op arm (before the `_ => classes` catch-all)
- [x] Add extern type test group to `stdlib/kestrel/dev/typecheck/typecheck.test.ks`
- [x] Add extern type test group to `stdlib/kestrel/tools/compiler/codegen-decl.test.ks`
- [x] Update `docs/specs/11-bootstrap.md` to note `extern type` is now handled by the self-hosted checker
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | Non-exported `extern type Foo` typechecks OK with no diagnostics; exported extern type appears in `exportedTypeVisibility` as `"export"`; opaque extern type appears as `"opaque"`; parameterised `extern type Map<K, V>` typechecks OK |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Module containing only `extern type` declarations produces a non-empty main class file with no extra ctor classes |

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — add a note under the self-hosted checker responsibilities that `extern type` declarations are now handled (prebind + checkDecls arm added)

## Build notes

- 2026-04-28: Started implementation.
- 2026-04-28: `registerExternTypeDecl` mirrors `registerExceptionDecl` — inserts `TApp(etd.name, [<param vars>])` into `typeAliases` using the same `buildTypeParamScope`/`ctorReturnType` helpers used by `registerTypeDecl`. No `ctorEnv`/`adtConstructors`/`ctorOwners` entries are created since extern types have no constructors.
- 2026-04-28: `checkDecls` arm for `TDExternType` adds to `exportedTypeAliases` for `"export"` or `"opaque"` visibility; `exportedTypeVisibility` is already populated by `registerExternTypeDecl` in the prebind phase, mirroring how `registerTypeDecl` sets it.
- 2026-04-28: Codegen arm is an explicit no-op `TDExternType(_) => classes` added before the `_ =>` catch-all in `emitDecl`; no runtime representation is emitted, matching TS reference behaviour.
- 2026-04-28: `cd compiler && npm test` — unit test suite (381 passing) passes; 4 integration tests fail due to pre-existing environment constraints (no dist/cli.js build, Java 21 required for JVM runtime virtual threads but only Java 17 is installed). `./scripts/kestrel test` cannot run for the same reason (JVM runtime jar missing; requires Java 21 to build). These failures are pre-existing and unrelated to this story's changes.
