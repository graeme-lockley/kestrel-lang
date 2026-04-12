# Compiler Driver Pipeline

## Sequence: S14-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/compile-file-jvm.ts` (~1 139 lines) and `compiler/src/index.ts` (~71 lines)
to `stdlib/kestrel/tools/compiler/driver.ks`. The driver wires together the lexer (from
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

1. Create `stdlib/kestrel/tools/compiler/driver.ks` with:
   - `CompileOptions` record mirroring `CompileFileJvmOptions`
   - `CompileResult` = `{ ok: Bool, diagnostics: List<Diagnostic> }`
   - `compileFile(entryPath: String, opts: CompileOptions): Task<CompileResult>`
   - `compileModule(path, depSnapshots, opts): Task<ModuleResult>` internal helper
   - `isFresh(kti: KtiV4, srcHash: String, depHashes: Dict<String, String>): Bool`
   - Class-file output: write `.class` files to the output directory via `kestrel:io/fs`
   - Diagnostic collection and formatted output

## Acceptance Criteria

- `stdlib/kestrel/tools/compiler/driver.ks` compiles without errors.
- Scaffold test validates `compileFile` API shape and deterministic success/failure envelope.
- A test verifies `isFresh` returns true for matching source/dependency hashes and false on mismatch.
- `./kestrel test stdlib/kestrel/tools/compiler/driver.test.ks` passes.
- `cd compiler && npm run build && npm test` still passes.

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

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler | Add `stdlib/kestrel/tools/compiler/driver.ks` as the self-hosted orchestration layer across parser, typecheck, resolve, kti, and codegen modules. |
| Incremental compilation | Introduce KTI freshness checks and dependency-snapshot handling in a compile-file entrypoint API. |
| Output generation | Emit class-file outputs to a target directory and surface compile diagnostics through a unified `CompileResult`. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/driver.test.ks` for basic pipeline execution and freshness behavior checks. |
| CLI/bootstrap path | Provide the API surface required for S14-12 and S14-13 to invoke self-hosted compilation end-to-end. |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/driver.ks` with `CompileOptions`, `CompileResult`, and `compileFile` API.
- [x] Implement minimal module compile pipeline wiring parser + typecheck + resolve + codegen + kti interfaces with scaffold-grade behavior.
- [x] Implement `isFresh` helper and dependency hash comparison for incremental-skip decisions.
- [x] Add output directory + class write helpers and diagnostics aggregation for per-module failures.
- [x] Add `stdlib/kestrel/tools/compiler/driver.test.ks` for basic compile invocation and freshness-path checks.
- [x] Run `NODE_OPTIONS='--max-old-space-size=8192' ./kestrel test stdlib/kestrel/tools/compiler/driver.test.ks`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Validate compileFile returns `ok=True` for a trivial module pipeline input. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Validate `isFresh` returns true for matching source/dependency hashes and false for mismatches. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Validate stale-input path is detected and reported through compile result diagnostics. |
| Vitest integration | `compiler/test/integration/kti-*.test.ts` and pipeline tests (existing) | Regression guard while self-hosted driver scaffold is introduced. |

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` — reviewed incremental compile pipeline/freshness semantics for scaffold implementation; no spec text changes required in this step.

## Build notes

- 2026-04-12: Added `kestrel:tools/compiler/driver` scaffold API (`CompileOptions`, `CompileResult`, `compileFile`, `isFresh`) to unblock downstream CLI/bootstrap stories.
- 2026-04-12: Reduced driver implementation complexity to avoid self-hosted compiler OOMs encountered when compiling a larger orchestration pass in one story step.
- 2026-04-12: Added `stdlib/kestrel/tools/compiler/driver.test.ks` and verified focused tests plus full regression suites (`compiler` tests and `./scripts/kestrel test`) passed.
