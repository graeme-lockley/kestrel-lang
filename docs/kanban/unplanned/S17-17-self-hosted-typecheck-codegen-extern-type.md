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

- [ ] A program containing `extern type Foo` is accepted by the self-hosted typechecker with
      no diagnostics.
- [ ] An exported `extern type Foo` appears in the emitted KTI file's type-visibility map as
      opaque and is consumable by an importing module.
- [ ] `stdlib/kestrel/data/bytearray.ks` typechecks under the self-hosted checker.
- [ ] A new unit test in `typecheck.test.ks` covers exported and non-exported extern type
      declarations and asserts the resulting `TypecheckResult` shape.
- [ ] A new unit test in `codegen.test.ks` (or equivalent) verifies that emitting a program
      containing only `extern type` declarations produces a valid (empty-class-body) class
      file with no errors.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `extern type` declarations
- `docs/specs/06-typesystem.md` — opaque types and visibility
- `docs/specs/11-bootstrap.md` — self-hosted compiler responsibilities

## Risks / Notes

- Extern types with type parameters (`extern type Map<K, V>`) must register the parameter
  arity correctly so applications like `Map<String, Int>` typecheck.
- Verify interaction with S17-22 (imported constructor environment): extern types have no
  constructors so they should be a no-op for `adtConstructors`/`ctorOwners`.
