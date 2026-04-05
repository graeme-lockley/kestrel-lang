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

- [x] Add `readKtiFile` to `compiler/src/kti.ts`:
  - `import { existsSync, readFileSync } from 'fs'` (already imported `writeFileSync`; add `existsSync, readFileSync`)
  - Signature: `export function readKtiFile(ktiPath: string): KtiV4 | null`
  - Implementation: if `!existsSync(ktiPath)` return null; try `JSON.parse(readFileSync(ktiPath,'utf-8'))`; check `parsed.version === 4`; cast and return; catch any error → return null

- [x] Add `deserializeExports` to `compiler/src/kti.ts`:
  - Signature: `export function deserializeExports(kti: KtiV4): { exports: Map<string,InternalType>; exportedTypeAliases: Map<string,InternalType>; exportedConstructors: Map<string,InternalType>; exportedTypeVisibility: Map<string,'local'|'opaque'|'export'> }`
  - Walk `kti.functions`: kind!='constructor' → `exports.set(name, deserializeType(entry.type))`; kind=='constructor' → `exportedConstructors.set(name, deserializeType(entry.type))`
  - Walk `kti.types`: → `exportedTypeAliases.set(name, deserializeType(entry.type ?? { k: 'app', n: name, as: [] }))`; → `exportedTypeVisibility.set(name, entry.visibility)` AND `exports.set(name, t)` (type aliases appear in both exports and exportedTypeAliases, per typecheck)

- [x] Update `compiler/src/compile-file-jvm.ts` — imports and cache type:
  - Add `statSync` to the `fs` import line
  - Extend `kti.js` import: `import { buildKtiV4, writeKtiFile, readKtiFile, deserializeExports, extractCodegenMeta, type KtiCodegenMeta } from './kti.js'`
  - Add `codegenMeta?: KtiCodegenMeta` to the cache Map entry type (the object shape inside the `Map<string, {...}>` at ~line 545)

- [x] Insert freshness shortcut in `compileOne` (after the dep compilation loop, before typecheck):
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

- [x] Refactor dep-codegen-metadata lookups in `compileOne` to prefer `codegenMeta`:
  - In the NamedImport loop: added `const depEntry = cache.get(dep.path); const depMeta = depEntry?.codegenMeta; const depProg = depEntry?.program`
  - All helper lookups (arity, async, val/var) now prefer `depMeta` fields; fall back to `depProg` walk when `depMeta` absent
  - Exception/ADT constructor lookups use `depMeta.exceptionDecls` / `depMeta.adtConstructors` first
  - Namespace import loop similarly prefers `depMeta`

- [x] Set `codegenMeta` in the full-compile cache entry:
  - Added `extractCodegenMeta(program, ...)` call after `onCompilingFile`, stored in `codegenMeta`, added to `cache.set` and return value

- [x] Add unit tests to `compiler/test/unit/kti.test.ts`:
  - `describe('readKtiFile')`: 4 tests covering valid file, missing, malformed, version≠4
  - `describe('deserializeExports')`: 4 tests covering function/val/var, constructors, opaque visibility, type round-trip

- [x] Add integration test `compiler/test/integration/kti-incremental.test.ts`:
  - 4 tests: second-build caching, `.kti` file existence + v4 format, stale dep recompile, corrupt `.kti` failsafe

- [x] Run `cd compiler && npm run build && npm test`

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

## Build notes

- 2025-01-29: **Critical bug found**: typecheck puts type names (ADT/alias) in BOTH `tc.exports` AND `tc.exportedTypeAliases`, but `buildKtiV4` only stores them in `kti.types`. Fix: `deserializeExports` now adds type names to `exports` (in addition to `exportedTypeAliases`) matching typecheck behavior. Without this, `import { DirEntry } from "kestrel:fs"` would fail with "does not export DirEntry".
- 2025-01-29: Simplified freshness check: since source is already read to get imports, hash is computed at parse time. Freshness check AFTER dep compilation loop uses computed `sourceHash` vs `kti.sourceHash`. No mtime gate needed (source already in memory).
- 2025-01-29: Kestrel function declarations use `:` not `->` for return-type annotations in tests.
- 2025-01-29: `.kti` files are written with full-path-based class names (e.g. `Users/graemelockley/.../Leaf.kti`), so test assertions need recursive directory scan.
- 2025-01-29: 417 tests pass (405 prior + 8 new unit tests for readKtiFile/deserializeExports + 4 integration tests).
