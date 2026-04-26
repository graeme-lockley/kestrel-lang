# Topological dependency ordering and cycle detection

## Sequence: S17-07
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Build a full import graph (recursively from the entry file), topologically sort it, detect
circular imports, and compile each module in dependency order. Each module is compiled once
per invocation (deduplicated by absolute path).

## Current State

After S17-06, the driver can load cross-module types for direct dependencies. But it only
compiles the entry file — if `a.ks` imports `b.ks` and `b.ks` is not pre-compiled, compilation
fails. This story adds recursive graph building and topological ordering so all dependencies
are compiled before the modules that use them.

## Relationship to other stories

- **Depends on**: S17-06 (cross-module KTI loading required for multi-module compile)
- **Blocks**: S17-08 (incremental compilation operates over the full graph)

## Goals

1. Build a dependency graph: starting from `entryPath`, recursively parse each dependency to
   find its imports, resolve them, and collect the transitive closure.
2. Topologically sort the graph (dependencies first, dependents last).
3. Detect cycles: if a circular import is found, return `ok=False` with a diagnostic naming
   the cycle members.
4. Compile modules in topological order, each time using the KTI outputs of already-compiled
   modules as import bindings.
5. Deduplicate: if the same absolute path appears multiple times in the graph (diamond deps),
   compile it only once.

## Acceptance Criteria

- [x] A two-module program (entry imports helper) compiles correctly end-to-end.
- [x] A circular import returns `ok=False` with a diagnostic naming the cycle.
- [x] Diamond dependency pattern (A→B, A→C, B→C) compiles `C` only once.
- [x] `driver.test.ks` has tests for the two-module success path and cycle detection.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — import graph and topological ordering

## Risks / Notes

- The graph must be built by parsing only (not typechecking) each file to discover imports —
  this is a lightweight pre-pass.
- Topological sort: Kahn's algorithm or DFS-based; both are fine. The TypeScript compiler uses
  a DFS approach.
- stdlib files also have transitive deps; include them in the graph if their `.ks` source is
  readable, but note that stdlib modules may already have pre-built KTI files.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler driver | `stdlib/kestrel/tools/compiler/driver.ks`: add recursive dependency-graph pre-pass (parse + resolve only), DFS cycle detection, topological ordering, dedupe-by-absolute-path, and ordered compile execution before typecheck/codegen |
| Stdlib compiler resolver | `stdlib/kestrel/tools/compiler/resolve.ks` (optional helper extraction only): keep `resolveSpecifier`/`uniqueDependencyPaths` behavior aligned with graph traversal call sites in driver |
| Kestrel compiler tests | `stdlib/kestrel/tools/compiler/driver.test.ks`: add two-module success path and cycle detection tests; add compile-once assertion for diamond pattern |
| Kestrel compiler tests | `stdlib/kestrel/tools/compiler/driver-kti-loading.test.ks` (if needed): keep focused cross-module KTI loading assertions green after graph-order changes |
| Specs/docs | `docs/specs/07-modules.md`: document that self-hosted driver rejects import cycles with a compile diagnostic and compiles DAG dependencies in topological order |

Compatibility/risk notes:
- Graph pre-pass must only parse and resolve imports, not typecheck/codegen, to keep memory/runtime bounded.
- Cycle diagnostics should name cycle members deterministically (stable path order) to avoid flaky tests.
- Keep compile ordering deterministic across runs (absolute-path keyed traversal).

## Tasks

- [x] Add dependency graph model + DFS traversal helpers in `stdlib/kestrel/tools/compiler/driver.ks` to recursively discover transitive imports from `entryPath`.
- [x] Add parse-only file loading helper in `driver.ks` (read + lex + parse + import extraction) used by graph traversal; propagate parse/resolve diagnostics through `CompileResult`.
- [x] Add cycle detection in DFS traversal in `driver.ks`; return `ok=False` with diagnostic naming cycle members when back-edge is found.
- [x] Add topological order output (dependencies first) and dedupe-by-absolute-path in `driver.ks`.
- [x] Refactor compile pipeline in `driver.ks` so `compileFile` compiles every module in topo order exactly once, with entry module compiled last.
- [x] Ensure per-module KTI loading in ordered compile path uses already-compiled dependency KTIs from `opts.outDir`.
- [x] Add/adjust helper(s) in `stdlib/kestrel/tools/compiler/resolve.ks` only if needed to keep traversal call sites simple and deterministic.
- [x] Add test in `stdlib/kestrel/tools/compiler/driver.test.ks`: two-module success path (entry imports helper; compile entry succeeds end-to-end).
- [x] Add test in `stdlib/kestrel/tools/compiler/driver.test.ks`: cycle detection path returns `ok=False` and diagnostic mentions cycle files.
- [x] Add test in `stdlib/kestrel/tools/compiler/driver.test.ks`: diamond graph compiles shared dep once per invocation (dedupe guard).
- [x] Update `docs/specs/07-modules.md` for self-hosted cycle rejection + topo compile ordering behavior.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Two-module success: compile helper first via graph ordering, then entry uses helper export with no missing-KTI error |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Cycle detection: `a.ks -> b.ks -> a.ks` returns `ok=False` and diagnostic names both `a.ks` and `b.ks` |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Diamond dedupe: `A -> {B,C}, B -> C` compiles `C` only once in a single compile invocation |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver-kti-loading.test.ks` | Regression guard: named/namespace KTI loading remains correct under topo-ordered multi-module compile |

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` — document self-hosted driver graph traversal behavior (recursive import graph build), deterministic topological compile order, and cycle rejection diagnostic expectations.

## Build notes

- 2026-04-26: Started implementation.
- 2026-04-26: Canonicalized graph traversal paths before visited/cycle checks so equivalent paths (for example `/a.ks` and `/./a.ks`) do not bypass cycle detection or dedupe.
- 2026-04-26: Implemented topological compilation via DFS post-order recursion (dependencies compiled before dependents) while preserving existing per-module KTI loading in `doTypecheckAndEmit`.
