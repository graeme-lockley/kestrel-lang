# `.kti` v4 Writer in `compile-file-jvm.ts`

## Sequence: S07-02
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E07 Incremental Compilation](../epics/unplanned/E07-incremental-compilation.md)
- Companion stories: S07-01 (spec), S07-03 (reader + freshness routing), S07-04 (--clean flag)

## Summary

After `compile-file-jvm.ts` successfully compiles a package (typecheck + JVM codegen), it currently writes `.class` files and a `.class.deps` file but nothing else persistent. This story adds a `.kti` writer: after each successful package compilation, serialize the package's typecheck exports (`exports`, `exportedTypeAliases`, `exportedConstructors`, `exportedTypeVisibility`), JVM codegen metadata (function arities, async flags, val/var/exception/ADT info), `sourceHash` (SHA-256 of the source), and `depHashes` (SHA-256 of each direct dep's source) into a v4 `.kti` JSON file written alongside the `.class` output.

## Current State

- `compile-file-jvm.ts` writes `.class`, `<className>.class.deps`, `.kdeps`, and `.extern.ks` sidecars after each package compile, but no `.kti`.
- The in-process `cache` Map stores `{ program, jvmResult, dependencyPaths, className, exports, exportedTypeAliases, exportedConstructors, exportedTypeVisibility, mavenDeps }` — all the data needed for the writer, except `sourceHash` and `depHashes` (which must be computed from source content).
- `InternalType` is the type used for exports; it must be serialized to the `SerType` JSON encoding defined in `kti-format.md` (S07-01).

## Relationship to other stories

- **Depends on S07-01**: the writer must implement the v4 format spec defined there.
- **Must be done before S07-03**: the reader tests need `.kti` files produced by the writer.
- Independent of S07-04.

## Goals

- After every successful package compile, a `.kti` v4 file is written alongside the `.class` output.
- The `.kti` faithfully captures all information needed by the reader to restore typecheck exports and provide JVM codegen metadata, with no source re-read required by the reader.

## Acceptance Criteria

- After `compileFileJvm()` runs on a multi-package project, each compiled package has a `<ClassName>.kti` file in its output directory.
- The `.kti` file parses as valid JSON with `version: 4`, `sourceHash` (64-char hex), `depHashes` (object), `functions` (v3 export entries), `types` (v3 type entries), and `codegenMeta` (all sub-fields per spec).
- `sourceHash` is the SHA-256 (hex) of the UTF-8 source content of that package's `.ks` file at the time of compilation.
- `depHashes` contains one entry per direct source dependency (resolved absolute path → SHA-256 hex of that dep's source). Maven deps and non-source deps are excluded.
- `codegenMeta.funArities` correctly reflects the arity of every exported function and extern fun.
- `codegenMeta.asyncFunNames` correctly identifies all exported async functions (including extern funs with `Task<T>` return).
- `codegenMeta.varNames` and `codegenMeta.valOrVarNames` correctly list exported var/val declarations.
- `codegenMeta.adtConstructors` lists all exported non-opaque ADT types and their constructors with correct param counts.
- `codegenMeta.exceptionDecls` lists all exported exceptions with correct field counts.
- Unit tests in `compiler/test/unit/` cover the serialization of all export entry kinds and all `SerType` variants via round-trip.
- Conformance: an existing multi-package integration test (or new one) verifies `.kti` files are written on a successful build.

## Spec References

- `docs/specs/kti-format.md` — v4 format (to be created in S07-01)
- `docs/specs/07-modules.md §5` — types file spec

## Risks / Notes

- `InternalType` serialization must handle all variants including `union`, `inter`, `scheme`, `namespace`, and recursive types. The old VM implementation (`done/30-types-file-full-spec07`) had round-trip tests; those test cases should be ported.
- The writer runs only when `getClassOutputDir` is set (i.e. when the compiler is invoked with `-o`). The `.kti` is written to the same directory as the `.class` file.
- Writing the `.kti` after `.class` ensures that a partial build (crash after `.class` but before `.kti`) leaves no stale `.kti`; on the next run the `.class` is present but `.kti` is absent, which falls through to a full recompile (correct behaviour).
- The `.kti` write path should mirror the `.class` write path: `pathResolve(classDir, className + '.kti')`.
