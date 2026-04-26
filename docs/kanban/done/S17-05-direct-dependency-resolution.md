# Direct dependency path resolution from a single source file

## Sequence: S17-05
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Call `Resolve.uniqueDependencyPaths` on the parsed program to obtain the flat list of
`ResolvedDep` values for direct imports. No multi-module compile yet; just prove the paths
are correctly resolved for stdlib and relative specifiers.

## Current State

`stdlib/kestrel/tools/compiler/resolve.ks` already implements `uniqueDependencyPaths`. The driver
currently typechecks with no import bindings (ignoring all imports). This story wires the resolver
into the pipeline so that direct import paths are identified, but compilation still proceeds
without loading the dependency types.

## Relationship to other stories

- **Depends on**: S17-01 (single-file pipeline), S17-04 (freshness check)
- **Blocks**: S17-06 (cross-module KTI type loading uses resolved dep paths)

## Goals

1. After parsing the program, call `Resolve.uniqueDependencyPaths(prog, entryPath, resolveOpts)`
   to get the direct dependency paths.
2. Build `resolveOpts` from the driver's `CompileOptions` (stdlibDir, cacheRoot, allowHttp,
   fromFile=entryPath).
3. If resolution fails (e.g. invalid specifier), return `ok=False` with an error diagnostic.
4. Log/return the resolved dep list — it will be used in S17-06 to load dep KTIs.
5. No change to typecheck invocation yet (still passes empty import bindings).

## Acceptance Criteria

- [x] `compileFile` calls `Resolve.uniqueDependencyPaths` and captures the dep list.
- [x] A resolution error returns `ok=False` with a diagnostic.
- [x] `driver.test.ks` verifies that stdlib import specifiers resolve correctly.
- [x] `driver.test.ks` verifies that a bad specifier produces an error result.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — module resolution
- `docs/specs/11-bootstrap.md` — self-hosted pipeline

## Risks / Notes

- `resolveOpts.stdlibDir` must point to the actual stdlib directory; it comes from
  `opts.stdlibDir` in `CompileOptions`.
- `maven:` specifiers need special handling in later stories (S17-11); for now they can be
  passed through and ignored (they won't resolve to a `.ks` path).

## Impact analysis

- `stdlib/kestrel/tools/compiler/driver.ks`: import `Resolve`; after `ParseOk(prog)`, call `Resolve.uniqueDependencyPaths(prog, entryPath, resolveOpts)`; on `Err` return diagnostic; on `Ok(deps)` continue with typecheck (deps unused in this story)
- `stdlib/kestrel/tools/compiler/driver.test.ks`: add test for bad specifier returns error; existing tests cover happy-path (programs with no imports resolve OK)

## Tasks

- [x] Add `import * as Resolve from "kestrel:tools/compiler/resolve"` to driver.ks
- [x] After `ParseOk(prog)`, build `resolveOpts` from `CompileOptions` fields and call `Resolve.uniqueDependencyPaths`
- [x] On resolution `Err`: return `failWithDiags([diag(..., CODES.resolve.moduleNotFound, msg)])`
- [x] Add test: file with bad import specifier (e.g. `kestrel:../bad`) returns ok=False with diagnostic
- [x] Run `./scripts/kestrel test`

## Tests to add

- `driver.test.ks`: bad specifier test (`kestrel:../bad`) verifies resolution failure diagnostic

## Documentation and specs to update

- [x] No spec changes needed; mark reviewed

## Build notes

- 2026-04-26: Implemented. Wired `Resolve.uniqueDependencyPaths` into pipeline after parse. Used `kestrel:../bad` import to test resolution error path.
