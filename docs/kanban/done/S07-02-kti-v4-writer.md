# `.kti` v4 Writer in `compile-file-jvm.ts`

## Sequence: S07-02
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E07 Incremental Compilation](../epics/done/E07-incremental-compilation.md)
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

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/kti.ts` | New file: `SerType` serializer/deserializer, `KtiCodegenMeta` extractor, `buildKtiV4`, `writeKtiFile` |
| `compiler/src/compile-file-jvm.ts` | Add `sourceHash: string` to cache entry; import `createHash` from `node:crypto`; call `writeKtiFile` after writing `.class` files inside `if (getClassOutputDir)` guard |
| `compiler/test/unit/kti.test.ts` | New unit tests for serialization round-trips and codegen meta extraction |

## Tasks

- [x] Create `compiler/src/kti.ts`:
  - Define `KtiExportEntry` discriminated union type (function/val/var/constructor/type kinds matching kti-format.md §3)
  - Define `KtiTypeEntry` type (visibility + kind + type + optional constructors/typeParams)
  - Define `KtiCodegenMeta` type (`funArities`, `asyncFunNames`, `varNames`, `valOrVarNames`, `adtConstructors`, `exceptionDecls`)
  - Define `KtiV4` type (version/functions/types/sourceHash/depHashes/codegenMeta)
  - Implement `serializeType(t: InternalType): unknown` — covers all `InternalType` kinds: `prim` → `{k:'prim',n}`, `var` → `{k:'var',id}`, `arrow` → `{k:'arrow',ps,r}`, `record` → `{k:'record',fs,row}`, `app` → `{k:'app',n,as}`, `tuple` → `{k:'tuple',es}`, `union` → `{k:'union',l,r}`, `inter` → `{k:'inter',l,r}`, `scheme` → `{k:'scheme',vs,b}`, `namespace` → throw (never exported)
  - Implement `deserializeType(obj: unknown): InternalType` — inverse for tests (and later S07-03 reader)
  - Implement `extractCodegenMeta(program: Program, exports: Map<string, InternalType>, exportedTypeAliases: Map<string, InternalType>, exportedTypeVisibility: Map<string, 'local' | 'opaque' | 'export'>): KtiCodegenMeta`:
    - Walk `program.body` once; for each node kind: FunDecl → funArities + asyncFunNames, ExternFunDecl → funArities + asyncFunNames (check `returnType` for `AppType` name `Task`), ValDecl → valOrVarNames, VarDecl → varNames + valOrVarNames, TypeDecl with ADTBody and visibility ≠ 'opaque' → adtConstructors entry, ExceptionDecl with `exported: true` → exceptionDecls entry
    - Only include names in `exports` or `exportedTypeAliases` (to exclude internal declarations)
  - Implement `buildKtiV4(params: { program, source, depResults, exports, exportedTypeAliases, exportedConstructors, exportedTypeVisibility, cache }): KtiV4`:
    - `sourceHash` = `createHash('sha256').update(source,'utf8').digest('hex')`
    - `depHashes` = for each depPath in depResults, look up `cache.get(depPath)?.sourceHash`
    - `functions` map = built per kti-format.md §3; use `function_index: 0` (JVM doesn't use index; set to 0 as placeholder per spec)
    - `types` map = from `exportedTypeAliases` + `exportedTypeVisibility` + program body (to distinguish alias vs adt)
    - `codegenMeta` = from `extractCodegenMeta`
  - Export `writeKtiFile(ktiPath: string, kti: KtiV4): void` — writes `JSON.stringify(kti, null, 2) + '\n'`

- [x] Update `compiler/src/compile-file-jvm.ts`:
  - Add `import { createHash } from 'node:crypto';`
  - Add `sourceHash: string` field to the `cache` Map entry type
  - At the point where `source` is read (before parsing), compute `const sourceHash = createHash('sha256').update(source, 'utf8').digest('hex');`
  - Add `sourceHash` to the `cache.set(...)` call and the return value
  - Inside `if (getClassOutputDir)` block, after all `.class` and sidecar file writes, call `writeKtiFile(pathResolve(classDir, jvmResult.className + '.kti'), buildKtiV4({...}))` passing `source`, `sourceHash`, `depResults`, `tc.*`, `cache`

- [x] Create `compiler/test/unit/kti.test.ts`:
  - `describe('serializeType')`: test all InternalType variants → correct `k` and fields
  - `describe('deserializeType')`: round-trip for each variant (serializeType → deserializeType → deep-equals original)
  - `describe('extractCodegenMeta')`: build minimal Programs with FunDecl/VarDecl/TypeDecl/ExceptionDecl and verify each codegenMeta field
  - `describe('buildKtiV4')`: build a KtiV4 from a sample program and assert `version: 4`, `sourceHash` is 64 hex chars, all fields present

- [x] Run `cd compiler && npm run build && npm test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/kti.test.ts` | `serializeType` and `deserializeType` round-trips for all 10 InternalType variants |
| Vitest unit | `compiler/test/unit/kti.test.ts` | `extractCodegenMeta` for FunDecl, VarDecl, ADT TypeDecl, ExceptionDecl |
| Vitest unit | `compiler/test/unit/kti.test.ts` | `buildKtiV4` produces v4 JSON with correct top-level fields |
| Vitest integration | `compiler/test/integration/` | After `compileFileJvm`, each compiled package has a `.kti` file with valid v4 JSON |

## Documentation and specs to update

- [ ] `docs/specs/kti-format.md` — no change needed (spec written in S07-01)

## Spec References

- `docs/specs/kti-format.md` — v4 format (created in S07-01)
- `docs/specs/07-modules.md §5` — types file spec

## Build notes

- 2025-01-29: `function_index` and `setter_index` are set to `0` as JVM placeholder values. The JVM pipeline resolves calls by class name + method name (`invokestatic`), not by index. The reader (S07-03) will use the type field only; the index fields remain in the format for potential VM-target use.
- 2025-01-29: `prim` type cast required a union cast `n as ('Int' | 'Float' | 'Bool' | 'String' | 'Unit' | 'Char' | 'Rune')` instead of intersection (`InternalType & { kind: 'prim' }['name']`), which TypeScript rejects structurally.
- 2025-01-29: `depSourceHashes` is built from the in-process `cache` Map — all transitive deps are compiled before the current package (topological order guaranteed by recursion), so their `sourceHash` is always available without re-reading files.
- 2025-01-29: `namespace` kind is the only `InternalType` variant that is never serialized (module-scope only). `serializeType` throws with a clear message.
- 2025-01-29: 405 tests pass (376 prior + 29 new kti unit tests). No regressions.
