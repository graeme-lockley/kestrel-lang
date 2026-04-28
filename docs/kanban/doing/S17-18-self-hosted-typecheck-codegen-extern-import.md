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

## Impact analysis

| Area | Change |
|------|--------|
| Self-hosted typecheck (`stdlib/kestrel/dev/typecheck/typecheck.ks`) | Add `TDExternImport` to named imports; add `registerExternImportSigs` helper; add `TDExternImport` arm in `prebindFunDecls`; add `checkExternImportDecl`/`checkExternImportOverrides` helpers; add `TDExternImport` arm in `checkDecls` |
| Self-hosted codegen (`stdlib/kestrel/tools/compiler/codegen.ks`) | Add `TDExternImport` to named imports; add `emitExternOverride` and `emitExternImportOverrides` helpers; add `TDExternImport` arm in `emitDecl` |
| Typecheck tests (`stdlib/kestrel/dev/typecheck/typecheck.test.ks`) | Add `extern import` typechecking group: no-diagnostics check, override names accessible in local env |
| Codegen tests (`stdlib/kestrel/tools/compiler/codegen-decl.test.ks`) | Add `extern import` codegen group: main class emitted with non-zero bytes |
| Spec (`docs/specs/11-bootstrap.md`) | Note that self-hosted typechecker/codegen now handle `extern import` |
| Naming convention risk | Override names are bound directly by their `name` field (e.g. `append`, not `SB.append`); this matches the TS compiler's expansion logic which names generated `ExternFunDecl` nodes by their Kestrel name, not by the alias. `extern import` is always local — the parser rejects `export extern import`. |
| KTI / extractCodegenMeta | No change needed: `extractCodegenMeta` works from the exported-name set, and `extern import` names are local-only, so they never reach the KTI `functions` map. |

## Tasks

- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `TDExternImport` to the named import list from `kestrel:dev/parser/ast`
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `registerExternImportSigs` helper (iterates `ExternOverride` list, inserts each `override.name → generalized arrow type` into env dict)
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `TDExternImport(eid)` arm in `prebindFunDecls` calling `registerExternImportSigs`
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `checkExternImportOverrides` + `checkExternImportDecl` helpers (bind each override name into env; no export since `extern import` is always local)
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `TDExternImport(eid)` arm in `checkDecls` calling `checkExternImportDecl`
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `TDExternImport` to the named import list from `kestrel:dev/parser/ast`
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `emitExternOverride` helper (emits a stub static method using `objectMethodDesc(arity)`) and `emitExternImportOverrides` list iterator
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `TDExternImport(eid)` arm in `emitDecl` calling `emitExternImportOverrides`
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.test.ks`: add `extern import declarations` test group
- [x] In `stdlib/kestrel/tools/compiler/codegen-decl.test.ks`: add `extern import declaration` test group
- [x] Update `docs/specs/11-bootstrap.md` — add note that self-hosted checker/codegen handle `TDExternImport`
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | `extern import` with two overrides produces no diagnostics; override names are accessible in the local type env (exported wrapper function using an override name typechecks) |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | `extern import` with two overrides produces a non-empty main class bytes in `JvmCodegenResult`; module does not throw during codegen |

## Documentation and specs to update

- [ ] `docs/specs/11-bootstrap.md` — add bullet noting that the self-hosted typechecker and codegen now handle `TDExternImport` (extern import declarations) without emitting "Unsupported top-level declaration" diagnostics

## Build notes

- 2026-04-28: Started implementation.
