# `.kti` Reader and Freshness Routing in `compile-file-jvm.ts`

## Sequence: S07-03
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E07 Incremental Compilation](../epics/unplanned/E07-incremental-compilation.md)
- Companion stories: S07-01 (spec), S07-02 (writer), S07-04 (--clean flag)

## Summary

`compile-file-jvm.ts` currently re-parses and re-typechecks every transitive dependency on every invocation. This story adds freshness routing: before recursing into a dependency's `compileOne()`, check whether a valid `.kti` file exists and is up to date. If it is, populate the in-process `cache` Map from the `.kti` — providing the typecheck export snapshot and JVM codegen metadata that downstream packages need — and skip the full parse/typecheck/codegen cycle for that package entirely. The freshness check uses a mtime gate as a fast-path (no source read), with a SHA-256 hash guard as a correctness fallback for CI environments with coarse timestamps.

## Current State

- `compileOne(filePath)` in `compile-file-jvm.ts` unconditionally reads source, tokenizes, parses, typechecks, and runs JVM codegen for every dependency. The in-process `cache` Map prevents re-work within a single invocation but nothing persists between runs.
- After S07-02 lands, `.kti` files will be written alongside `.class` output. This story reads them.
- The `cache` Map stores entries with shape `{ program, jvmResult, dependencyPaths, className, exports, exportedTypeAliases, exportedConstructors, exportedTypeVisibility, mavenDeps }`. When loading from `.kti`, `program` and `jvmResult` are not needed (downstream only reads the exports and codegen metadata), so a `.kti`-loaded entry uses synthetic/empty values for those fields.

## Relationship to other stories

- **Depends on S07-02**: needs `.kti` files to read.
- S07-04 (--clean) adds the bypass mechanism that makes freshness routing opt-out; the reader is always active unless `--clean` is passed.

## Goals

- A dep whose `.kti` passes the freshness check is never re-parsed or re-typechecked.
- Dependencies processed in topological order (leaves first); the dep-hash portion of the freshness check uses already-resolved dep hashes from the in-process cache — no extra I/O.
- Correctness: a stale `.kti` (source changed, dep changed, or version mismatch) always triggers a full recompile and fresh `.kti` write.

## Acceptance Criteria

- On the second invocation of `kestrel build` on an unchanged multi-package project, no `.ks` source files are read for dependencies (only `stat` calls and one small `.kti` JSON read per dep).
- A dep whose source changes is recompiled; its dependents are also recompiled (transitive invalidation via dep-hash mismatch).
- A dep whose `.kti` has `version` ≠ 4 triggers a full recompile (version rejection).
- A corrupt or unparseable `.kti` triggers a full recompile with no error reported to the user (fail-safe fallback).
- The `onCompilingFile` callback is NOT called for deps loaded from a fresh `.kti` (they were not compiled).
- Integration test: build a 3-package project twice; assert the second build completes with zero `onCompilingFile` calls for the leaf packages.
- Integration test: touch (modify) an intermediate package's source; assert only that package and its dependents are recompiled on the next build, not the unchanged leaf packages.
- All existing compiler unit and integration tests continue to pass.

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/kti.ts` | Add `readKtiFile(path): KtiV4 \| null` (safe read + version check) and `deserializeExports(kti): {exports, exportedTypeAliases, exportedConstructors, exportedTypeVisibility}` |
| `compiler/src/compile-file-jvm.ts` | Add `statSync` to fs import; add `KtiCodegenMeta, readKtiFile, deserializeExports, extractCodegenMeta` to kti.js import; add `codegenMeta?: KtiCodegenMeta` to cache entry type; insert freshness shortcut after dep compilation loop; refactor dep-codegen-metadata lookups to prefer `codegenMeta` over `depProg.body` walks; set `codegenMeta` in full-compile cache entry |
| `compiler/test/integration/kti-incremental.test.ts` | New integration test: second build zero re-compiles; touched dep triggers targeted recompile; corrupt `.kti` fails safe |
| `compiler/test/unit/kti.test.ts` | Add `describe('readKtiFile')` and `describe('deserializeExports')` unit tests |

## Tasks

- [ ] Add `readKtiFile` to `compiler/src/kti.ts`:
  - `import { existsSync, readFileSync } from 'fs'` (already imported `writeFileSync`; add `existsSync, readFileSync`)
  - Signature: `export function readKtiFile(ktiPath: string): KtiV4 | null`
  - Implementation: if `!existsSync(ktiPath)` return null; try `JSON.parse(readFileSync(ktiPath,'utf-8'))`; check `parsed.version === 4`; cast and return; catch any error → return null

- [ ] Add `deserializeExports` to `compiler/src/kti.ts`:
  - Signature: `export function deserializeExports(kti: KtiV4): { exports: Map<string,InternalType>; exportedTypeAliases: Map<string,InternalType>; exportedConstructors: Map<string,InternalType>; exportedTypeVisibility: Map<string,'local'|'opaque'|'export'> }`
  - Walk `kti.functions`: kind!='constructor' → `exports.set(name, deserializeType(entry.type))`; kind=='constructor' → `exportedConstructors.set(name, deserializeType(entry.type))`
  - Walk `kti.types`: → `exportedTypeAliases.set(name, deserializeType(entry.type ?? { k: 'app', n: name, as: [] }))`; → `exportedTypeVisibility.set(name, entry.visibility)`

- [ ] Update `compiler/src/compile-file-jvm.ts` — imports and cache type:
  - Add `statSync` to the `fs` import line
  - Extend `kti.js` import: `import { buildKtiV4, writeKtiFile, readKtiFile, deserializeExports, extractCodegenMeta, type KtiCodegenMeta } from './kti.js'`
  - Add `codegenMeta?: KtiCodegenMeta` to the cache Map entry type (the object shape inside the `Map<string, {...}>` at ~line 545)

- [ ] Insert freshness shortcut in `compileOne` (after the dep compilation loop, before typecheck):
  - After the closing `}` of `for (const spec of sourceSpecs)` dep compilation loop, add:
    ```
    if (getClassOutputDir && !(stalePaths?.has(filePath))) {
      const classDir = getClassOutputDir(filePath);
      const cn = classNameForPath(filePath);
      const ktiPath = pathResolve(classDir, cn + '.kti');
      const kti = readKtiFile(ktiPath);
      if (kti && kti.sourceHash === sourceHash) {
        // Check dep hashes against in-process cache
        let depHashesMatch = true;
        for (const dr of depResults) {
          if (kti.depHashes[dr.path] !== cache.get(dr.path)?.sourceHash) {
            depHashesMatch = false; break;
          }
        }
        if (depHashesMatch) {
          const deserialized = deserializeExports(kti);
          const depPaths = depResults.flatMap((d) => [d.path, ...d.dependencyPaths]);
          const dependencyPathsU = uniqueDependencyPaths([filePath, ...depPaths]);
          const entry = {
            program: { kind: 'Program', imports: [], topLevelDecls: [], body: [] } as unknown as Program,
            jvmResult: { className: cn, classBytes: new Uint8Array(), innerClasses: new Map() } as unknown as JvmCodegenResult,
            dependencyPaths: dependencyPathsU,
            className: cn,
            ...deserialized,
            mavenDeps: [] as MavenResolvedDependency[],
            sourceHash,
            codegenMeta: kti.codegenMeta,
          };
          cache.set(filePath, entry);
          visited.delete(filePath);
          return { ok: true, ...entry };
        }
      }
    }
    ```

- [ ] Refactor dep-codegen-metadata lookups in `compileOne` to prefer `codegenMeta`:
  - In the NamedImport loop (~line 770-805): replace `const depProg = cache.get(dep.path)?.program` with `const depEntry = cache.get(dep.path); const depMeta = depEntry?.codegenMeta; const depProg = depEntry?.program`
  - Replace `getFunArity(depProg, s.external)` → `depMeta?.funArities[s.external] ?? (depProg ? getFunArity(depProg, s.external) : undefined)`
  - Replace `isAsyncFun(depProg, s.external)` → `(depMeta?.asyncFunNames.includes(s.external) ?? false) || (!depMeta && depProg ? isAsyncFun(depProg, s.external) : false)`
  - Replace `isValOrVar(depProg, s.external)` → `depMeta ? depMeta.valOrVarNames.includes(s.external) : (depProg ? isValOrVar(depProg, s.external) : false)`
  - Replace `isVar(depProg, s.external)` → `depMeta ? depMeta.varNames.includes(s.external) : (depProg ? isVar(depProg, s.external) : false)`
  - Replace the `depProg.body` walk for ExceptionDecl/TypeDecl (importedAdtClasses) with a `codegenMeta`-based lookup; fall back to the existing body walk only when `depMeta` is absent
  - In the NamespaceImport loop (~line 810-843): similarly, prefer `depMeta` for FunDecl/ExternFunDecl/VarDecl/TypeDecl info when available; fall back to `depProg.body` walk

- [ ] Set `codegenMeta` in the full-compile cache entry:
  - In the `cache.set(filePath, {...})` call near the end of `compileOne`, add `codegenMeta: extractCodegenMeta(program, tc.exports, tc.exportedTypeAliases, tc.exportedTypeVisibility ?? new Map())`

- [ ] Add unit tests to `compiler/test/unit/kti.test.ts`:
  - `describe('readKtiFile')`: write valid KtiV4 JSON to a temp file → returns it; missing file → null; malformed JSON → null; version≠4 → null
  - `describe('deserializeExports')`: build a KtiV4 with function/val/var/constructor/type entries → verify all four maps are populated correctly with deserialized types

- [ ] Add integration test `compiler/test/integration/kti-incremental.test.ts`:
  - Setup: a two-package project (`leaf.ks` + `main.ks` importing leaf), compiled with a temp `getClassOutputDir`
  - Test 1 (second-build caching): compile once, then compile again; assert `onCompilingFile` is NOT called for `leaf.ks` on the second build
  - Test 2 (stale dep triggers recompile): compile, modify `leaf.ks` source, compile again; assert `onCompilingFile` IS called for both `leaf.ks` and `main.ks`
  - Test 3 (corrupt .kti failsafe): compile, corrupt the leaf's `.kti` (write garbage JSON), compile again; assert compilation succeeds with correct output

- [ ] Run `cd compiler && npm run build && npm test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/kti.test.ts` | `readKtiFile` reads valid, returns null on missing/malformed/wrong version |
| Vitest unit | `compiler/test/unit/kti.test.ts` | `deserializeExports` reconstructs all four Maps from a KtiV4 |
| Vitest integration | `compiler/test/integration/kti-incremental.test.ts` | Second-build caching (zero re-compiles); stale dep triggers targeted recompile; corrupt `.kti` failsafe |

## Documentation and specs to update

- (None — spec already updated in S07-01)

## Spec References

- `docs/specs/kti-format.md` — v4 format (S07-01)
- `docs/specs/07-modules.md §5` — freshness/invalidation algorithm (to be updated in S07-01)

## Risks / Notes

- **Three-step freshness check** (per epic Implementation Approach):
  1. **Fast-path (mtime gate)**: `.kti` exists + `version == 4` + `stat(.kti).mtime > stat(source).mtime` + all `depHashes` match the in-process cache's resolved hashes for those paths → load from `.kti`.
  2. **Slow-path (hash guard)**: mtime ambiguous (source mtime ≥ .kti mtime) → read source, compute SHA-256, compare against `.kti.sourceHash` AND check depHashes → load from `.kti` if all match.
  3. **Cache miss**: `.kti` absent, version mismatch, hash mismatch, or any parse error → fall through to full `compileOne` (existing path).
- **Synthetic cache entry**: when loading from `.kti`, set `program` to a minimal stub and `jvmResult` to an empty result. Downstream code in `compileOne` uses `depProg` (the `program` field) to extract codegen metadata; this must be replaced with data from `codegenMeta` in the `.kti`. The simplest approach: after S07-02, refactor the codegen-metadata extraction loop in `compileOne` to use a new `DepCodegenMeta` interface, populated either from `depProg` (full compile path) or from `kti.codegenMeta` (.kti path).
- **`getClassOutputDir` gating**: `.kti` reading and writing only applies when `getClassOutputDir` is configured. In-memory-only compilations (no `-o` flag) continue to compile everything from source.
- **Path normalisation**: keys in `depHashes` and in the in-process `cache` Map must use the same path form (already-resolved absolute paths). The reader must normalize `.kti` dep-hash keys the same way `compileOne` resolves specifiers.
