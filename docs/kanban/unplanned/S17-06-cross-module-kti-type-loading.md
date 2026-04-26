# Cross-module KTI type loading for the typechecker

## Sequence: S17-06
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Before typechecking a module, read the `.kti` files of each resolved direct dependency and
reconstruct the `importBindings` snapshot that the typechecker needs. Handle the case where a
dependency `.kti` is absent (dependency must be compiled first; return an error).

## Current State

After S17-05, the driver resolves direct dependency paths but passes empty import bindings to the
typechecker. Any program that imports another module will fail to typecheck correctly.

## Relationship to other stories

- **Depends on**: S17-05 (dependency paths are resolved)
- **Blocks**: S17-07 (multi-module topological compile needs working cross-module typecheck)

## Goals

1. For each resolved dependency path from S17-05, attempt to read the corresponding `.kti` file
   using `Kti.readKtiFile`.
2. If a dependency `.kti` is absent, return `ok=False` with a diagnostic indicating the dep
   must be compiled first.
3. Call `Kti.deserializeExports` (or equivalent) to reconstruct the `DependencyExportSnapshot`
   for each dep.
4. Freshen type variables in the imported types to avoid collisions (mirror the TypeScript
   `freshenImportedTypeVars` logic).
5. Pass the reconstructed `importBindings` to `typecheck`.

## Acceptance Criteria

- [ ] A module that imports a stdlib function typechecks correctly after its dep KTI is loaded.
- [ ] Missing dep KTI returns `ok=False` with a clear diagnostic.
- [ ] Type variable freshening prevents cross-module type variable ID collisions.
- [ ] `driver.test.ks` has a test covering the dep-KTI-missing error path.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — KTI and import bindings

## Risks / Notes

- Type variable freshening is critical for correctness in multi-module programs; the TypeScript
  implementation uses negative IDs to distinguish freshened vars. Replicate this carefully.
- `Kti.deserializeExports` may not exist in Kestrel yet; check `kti.ks` for the equivalent
  function and adapt.
- The KTI path for a dependency is: `<outDir>/<depModuleName>.kti` — derive this from the
  dep's absolute source path and `opts.outDir` (or the same directory as the dep's `.class` files).
