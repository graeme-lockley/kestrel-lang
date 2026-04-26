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

- [x] On second invocation with no source changes, no modules are recompiled.
- [x] Changing a dependency triggers recompilation of the dependency and all transitive dependents.
- [x] Dep hashes are computed as SHA-256 of the `.kti` file bytes (consistent with TS compiler).
- [x] `driver.test.ks` verifies the skip-all path and the cascade-recompile path.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — incremental compilation and dep hash scheme

## Risks / Notes

- `depHashes` must be computed from the `.kti` content of direct dependencies only (not
  transitive). Match the TypeScript compiler exactly.
- During a single invocation, in-memory `.kti` content (for modules compiled in this run) must
  be used for hashing, not re-read from disk.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler driver | `stdlib/kestrel/tools/compiler/driver.ks`: extend graph compile state to carry per-module dependency metadata and KTI content hashes; add freshness check per module before compile; skip fresh nodes while preserving downstream KTI availability. |
| KTI hashing path | `stdlib/kestrel/tools/compiler/driver.ks` + `stdlib/kestrel/tools/compiler/kti.ks` (if needed): compute `depHashes` from direct dependency `.kti` content bytes using SHA-256 and pass these hashes into `Kti.buildKtiV4`. |
| Kestrel compiler tests | `stdlib/kestrel/tools/compiler/driver.test.ks`: add graph-wide incremental tests for skip-all second compile and transitive cascade recompile after dependency source change; assert dep-hash values are derived from `.kti` content hashes. |
| Specs/docs | `docs/specs/07-modules.md`: document self-hosted graph-wide freshness behavior and direct-dependency `.kti` hash invalidation path for S17-08. |

Compatibility/risk notes:
- `depHashes` must remain direct-only (no transitive entries), matching TS behavior.
- Fresh-module skip must still leave dependency KTI data available for downstream import binding loads.
- Within one invocation, prefer in-memory KTI text for hashing when a dependency was just compiled.

## Tasks

- [x] Refactor graph compile state in `stdlib/kestrel/tools/compiler/driver.ks` to track per-module compile status plus `.kti` text snapshots for modules compiled or loaded fresh in the current invocation.
- [x] Add helper logic in `driver.ks` to build direct-dependency `depHashes` as SHA-256 of dependency `.kti` content bytes (from in-memory snapshot first, disk fallback second).
- [x] Update `compileOneModule`/`doTypecheckAndEmit` in `driver.ks` to perform per-module freshness checks using `Driver.isFresh(existingKti, srcHash, depHashes)` before typecheck/codegen, skipping fresh modules while preserving KTI snapshot state for dependents.
- [x] Ensure stale modules in `driver.ks` recompile and write updated `.kti` that includes computed direct dependency hashes.
- [x] Add test in `stdlib/kestrel/tools/compiler/driver.test.ks`: second invocation on unchanged multi-module graph recompiles no modules (skip-all path).
- [x] Add test in `stdlib/kestrel/tools/compiler/driver.test.ks`: mutating a dependency recompiles that dependency and transitive dependents but not unaffected modules.
- [x] Add test in `stdlib/kestrel/tools/compiler/driver.test.ks`: written `.kti.depHashes` values correspond to SHA-256 of direct dependency `.kti` content.
- [x] Update `docs/specs/07-modules.md` with self-hosted graph-wide freshness and direct dep `.kti` hash invalidation behavior.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Incremental skip-all: run compile twice on unchanged multi-module graph and assert module outputs/mtimes indicate no recompilation on second run. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Cascade recompile: change a shared dependency source, then assert dependency + transitive dependents are rebuilt while unchanged unrelated nodes are not. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Dep-hash scheme: inspect emitted `.kti` and assert direct dependency hash entries equal SHA-256 of direct dependency `.kti` file content. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver-kti-loading.test.ks` | Regression guard: cross-module KTI import binding loading remains correct under graph-wide freshness skipping. |

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` — document self-hosted graph-wide incremental freshness (per-module skip/recompile) and direct-dependency `.kti` hash invalidation behavior for S17-08.

## Build notes

- 2026-04-26: Started implementation.
- 2026-04-26: Reworked graph traversal state to carry both visited-compile flags and in-memory `.kti` text snapshots so downstream dep-hash checks can use freshly produced KTI content without extra disk reads.
- 2026-04-26: Added per-module dep-hash freshness checks in `compileOneModule` and threaded computed direct dependency hashes into `buildKtiV4` writes.
- 2026-04-26: Added S17-08 driver tests for unchanged-graph skip, transitive cascade invalidation, and direct-dependency `.kti` SHA-256 dep-hash encoding.
- 2026-04-26: Updated `docs/specs/07-modules.md` to document self-hosted graph-wide freshness semantics and dep-hash comparison against direct dependency `.kti` content hashes.
- 2026-04-26: Verification complete: `cd compiler && npm run build && npm test` and `./kestrel test` both passed after S17-08 changes.
