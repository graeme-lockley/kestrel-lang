# Self-hosted typecheck and codegen for `extern import` declarations

## Sequence: S17-18
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-16, S17-17, S17-19, S17-20, S17-21, S17-22, S17-23

## Summary

Teach the self-hosted typechecker and codegen to accept `extern import` declarations
(`TDExternImport`). These declarations bind one or more externally-provided functions
under a Kestrel alias and are required by any stdlib module that bridges the JVM (e.g.
`kestrel:io/fs`, `kestrel:io/process`, `kestrel:data/bytearray`).

Without this story, the self-hosted typechecker raises "Unsupported top-level declaration in
self-hosted checker MVP" and codegen has no emit path.

## Current State

- AST: `stdlib/kestrel/dev/parser/ast.ks` defines:
  ```
  ExternImportDecl = { target: String, alias: String, overrides: List<ExternOverride> }
  ExternOverride   = { name: String, params: List<Param>, retType: AstType }
  TDExternImport(ExternImportDecl)
  ```
- Typechecker: not handled in `prebindFunDecls`, `prebindTypeDecls`, or `checkDecls`
  (line 960 fall-through).
- Codegen: no `TDExternImport` arm in `emitDecl`.

## Relationship to other stories

- **Depends on**: S17-16 (the override signatures register a type that mirrors `extern fun`
  binding logic — implementing S17-16 first gives a reusable helper).
- **Blocks**: S17-23 (E2E).
- **Companion**: S17-17, S17-19, S17-20, S17-21, S17-22.

## Goals

1. In `prebindFunDecls` add a `TDExternImport(eid)` arm that, for each `ExternOverride`,
   binds `eid.alias <> "." <> override.name` (or whatever name scheme the parser uses) into
   the environment with its declared `(params) -> retType` type.
2. In `checkDecls` add the corresponding `TDExternImport(eid)` arm: registration only, no
   body inference; export visibility follows the declaration's exported flag.
3. In `codegen.ks`, add a `TDExternImport(eid)` arm to `emitDecl` that calls (or replicates)
   the existing `emitExternFun` logic for each override, so each declared name produces the
   correct JVM bridge method.
4. Confirm that a downstream module can import a name introduced by `extern import` via the
   normal KTI export path.

## Acceptance Criteria

- [ ] A program containing one `extern import` with two overrides typechecks with no
      diagnostics under the self-hosted checker.
- [ ] `stdlib/kestrel/io/fs.ks` (and any other stdlib file using `extern import`) typechecks
      and emits a valid class file via the self-hosted compiler.
- [ ] A new unit test covers a program that declares an extern import with at least two
      overrides and asserts both names are present in the resulting `exports` and KTI
      `functions` map.
- [ ] A new codegen unit test verifies that the bridge methods are emitted with correct
      method descriptors.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `extern import` declaration form
- `docs/specs/11-bootstrap.md` — self-hosted compiler responsibilities

## Risks / Notes

- Naming convention for the resulting binding (alias.name vs name) must match what the TS
  compiler produces, or downstream modules will fail to resolve imports across compiler
  variants. Cross-check `compiler/src/typecheck/check.ts` and `compiler/src/jvm-codegen`.
- Verify interaction with the codegen meta extracted into KTI (`extractCodegenMeta`).
