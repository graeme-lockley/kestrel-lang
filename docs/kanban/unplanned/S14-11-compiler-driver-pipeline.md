# Compiler Driver Pipeline

## Sequence: S14-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/compile-file-jvm.ts` (~1 139 lines) and `compiler/src/index.ts` (~71 lines)
to `stdlib/kestrel/compiler/driver.ks`. The driver wires together the lexer (from
`kestrel:dev/parser`), parser, type checker (S14-04), KTI reader/writer (S14-09),
module resolver (S14-10), and code generator (S14-07/S14-08) into the full multi-module
incremental compilation pipeline:

1. Resolve all transitive imports in topological order.
2. For each module, check KTI freshness (source hash + dep hashes).
3. If stale, lex + parse + typecheck + codegen → emit `.class` files + write new KTI.
4. Collect diagnostics; surface errors.

## Current State

`compiler/src/compile-file-jvm.ts`:
- `compileFileJvm(entryPath, options)` — top-level pipeline function
- `compileModule(path, depSnapshots, mavenDeps, options)` — single-module pipeline
- KTI freshness check: `isFresh(kti, sourceHash, depHashes): bool`
- Import binding preparation: `prepareImportBindings(kti, requestedImports)`
- Class output directory creation and `.class` file writing
- Error collection and propagation

`compiler/src/index.ts`:
- Thin re-export of `compileFileJvm`

## Relationship to other stories

- **Depends on**: all S14-01 through S14-10 (uses all compiler modules)
- **Blocks**: S14-12 (Kestrel CLI calls the driver), S14-13 (bootstrap uses driver)

## Goals

1. Create `stdlib/kestrel/compiler/driver.ks` with:
   - `CompileOptions` record mirroring `CompileFileJvmOptions`
   - `CompileResult` = `{ ok: Bool, diagnostics: List<Diagnostic> }`
   - `compileFile(entryPath: String, opts: CompileOptions): Task<CompileResult>`
   - `compileModule(path, depSnapshots, opts): Task<ModuleResult>` internal helper
   - `isFresh(kti: KtiV4, srcHash: String, depHashes: Dict<String, String>): Bool`
   - Class-file output: write `.class` files to the output directory via `kestrel:io/fs`
   - Diagnostic collection and formatted output

## Acceptance Criteria

- `stdlib/kestrel/compiler/driver.ks` compiles without errors.
- End-to-end test: compile `hello.ks` (or a trivial Kestrel program) through the self-hosted
  driver pipeline and confirm the output `.class` file runs correctly under `java`.
- A test verifies that re-compiling an unchanged module with a fresh KTI skips re-compilation
  (cache hit).
- A test verifies that modifying a source file invalidates the KTI and triggers recompilation.
- `./kestrel test stdlib/kestrel/compiler/driver.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/compile-file-jvm.ts`
- `compiler/src/index.ts`
- `docs/specs/07-modules.md` — incremental compilation and KTI freshness

## Risks / Notes

- Import binding preparation (`freshenImportedTypeVars`) in the TypeScript compiler uses a
  complex negative-id freshening trick; replicate it carefully to avoid type-variable collisions
  between modules.
- Maven dependency resolution (`resolveMavenSpecifiers`) is used for `maven://` imports; if the
  bootstrap path does not use Maven, stub it out but do not remove the interface.
- `onCompilingFile` callback in TypeScript is used by the CLI for progress reporting; expose an
  equivalent callback or async progress channel in the Kestrel driver.
- Class output directory creation (`mkdirSync`) must use `Fs.mkdir` from `kestrel:io/fs`
  (available since E13).
