# Self-hosted typecheck and codegen for `export * from` / `export { x } from` re-exports

## Sequence: S17-20
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-16, S17-17, S17-18, S17-19, S17-21, S17-22, S17-23

## Summary

Teach the self-hosted typechecker and codegen to handle re-export top-level declarations:

- `export * from "kestrel:..."` — re-exports every public name from the target module.
- `export { foo, bar } from "kestrel:..."` — re-exports a named subset.

Today the typechecker only handles `TDExport(EIDecl(decl))` (re-exporting a fresh local
declaration). The forwarding forms `EIStar` and `EINamed` fall through to the `_` arm and
emit "Unsupported top-level declaration in self-hosted checker MVP". Codegen has the same
gap.

## Current State

- AST defines:
  ```
  ExportInner =
      EIStar(String)                     // export * from "spec"
    | EINamed(String, List<ImportSpec>)  // export { x } from "spec"
    | EIDecl(TopDecl)
  TDExport(ExportInner)
  ```
- Typechecker handles `TDExport(EIDecl(_))` indirectly via the inner declaration arm but does
  not recognise `TDExport(EIStar(_))` or `TDExport(EINamed(_, _))`.
- Codegen has a `TDExport(inner)` arm with only an `EIDecl` sub-arm; the other shapes are
  not enumerated.

## Relationship to other stories

- **Depends on**: S17-16, S17-17, S17-18 (so the underlying value/type bindings to forward
  actually exist for stdlib modules).
- **Blocks**: S17-23 (E2E) for any stdlib aggregator module that uses re-exports.
- **Companion**: S17-19, S17-21, S17-22.

## Goals

1. Add `TDExport(EIStar(spec))` and `TDExport(EINamed(spec, specs))` arms to `checkDecls`.
   These arms must:
   - Look up the imported module's KTI exports (already loaded via `DepBindingBundle`),
   - Forward the selected (or all) value bindings into `exports`,
   - Forward the corresponding type-alias entries into `exportedTypeAliases`,
   - Forward the corresponding constructor entries into `exportedConstructors` and
     visibility into `exportedTypeVisibility`.
2. Add equivalent arms to `emitDecl` in `codegen.ks`. For pure re-exports, no bytecode is
   emitted (matching TS reference): the linkage is recorded in the KTI only.
3. Verify that downstream modules importing names through the re-export chain still resolve
   correctly via the existing `addNamedImportBindings` / `addNamedTypeAliasBindings` logic
   in `kti.ks`.

## Acceptance Criteria

- [ ] A program containing `export * from "kestrel:data/list"` typechecks with no
      diagnostics under the self-hosted checker.
- [ ] A program containing `export { foo, Bar } from "kestrel:other"` typechecks and emits
      a KTI whose `functions` and `types` sections include the forwarded names.
- [ ] At least one stdlib aggregator module that previously failed to typecheck under the
      self-hosted checker due to re-exports now succeeds.
- [ ] New unit tests in `typecheck.test.ks` cover both `EIStar` and `EINamed` forms,
      including the case where `EINamed` mixes value, type, and constructor names.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — re-export syntax
- `docs/specs/07-modules.md` — module export semantics

## Risks / Notes

- `EIStar` re-exports must respect type visibility (do not leak opaque internals as if they
  were public aliases). Cross-check with TS reference.
- Conflict with locally-defined names of the same identifier should produce a clear
  diagnostic (covered by S00-17 or similar in done/; verify the diagnostic still triggers
  under the self-hosted checker after this change).
