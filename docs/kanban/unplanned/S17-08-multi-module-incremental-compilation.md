# Multi-module incremental compilation (graph-wide freshness)

## Sequence: S17-08
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Apply the single-file freshness check (S17-04) across the full dependency graph. Only recompile
modules whose source has changed or whose dependencies have changed. Dep hashes are SHA-256
hashes of direct dependency `.kti` contents, matching the TypeScript compiler's scheme.

## Current State

After S17-07, all modules in the dependency graph are compiled in topological order. But every
module is recompiled on every invocation even if nothing changed. This story adds graph-wide
incremental compilation.

## Relationship to other stories

- **Depends on**: S17-07 (topological graph), S17-04 (single-file freshness)
- **Blocks**: S17-09 (URL deps are treated as graph nodes too)

## Goals

1. Before compiling each module in the topological order, check freshness:
   - Read the module's `.kti` file.
   - Compute `srcHash` for the module's source.
   - Compute `depHashes`: for each direct dependency, hash the contents of its `.kti` file
     (the `.kti` that was written in this invocation or read from disk).
   - Call `Driver.isFresh(kti, srcHash, depHashes)`.
2. If fresh, skip compilation of that module; use its existing `.kti` for downstream modules.
3. If stale, compile the module and write a new `.kti`.

## Acceptance Criteria

- [ ] On second invocation with no source changes, no modules are recompiled.
- [ ] Changing a dependency triggers recompilation of the dependency and all transitive dependents.
- [ ] Dep hashes are computed as SHA-256 of the `.kti` file bytes (consistent with TS compiler).
- [ ] `driver.test.ks` verifies the skip-all path and the cascade-recompile path.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — incremental compilation and dep hash scheme

## Risks / Notes

- `depHashes` must be computed from the `.kti` content of direct dependencies only (not
  transitive). Match the TypeScript compiler exactly.
- During a single invocation, in-memory `.kti` content (for modules compiled in this run) must
  be used for hashing, not re-read from disk.
