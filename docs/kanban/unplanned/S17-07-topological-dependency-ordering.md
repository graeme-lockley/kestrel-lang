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

- [ ] A two-module program (entry imports helper) compiles correctly end-to-end.
- [ ] A circular import returns `ok=False` with a diagnostic naming the cycle.
- [ ] Diamond dependency pattern (A→B, A→C, B→C) compiles `C` only once.
- [ ] `driver.test.ks` has tests for the two-module success path and cycle detection.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — import graph and topological ordering

## Risks / Notes

- The graph must be built by parsing only (not typechecking) each file to discover imports —
  this is a lightweight pre-pass.
- Topological sort: Kahn's algorithm or DFS-based; both are fine. The TypeScript compiler uses
  a DFS approach.
- stdlib files also have transitive deps; include them in the graph if their `.ks` source is
  readable, but note that stdlib modules may already have pre-built KTI files.
