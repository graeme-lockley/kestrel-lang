# Single-file freshness check (skip recompile if fresh)

## Sequence: S17-04
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Before compiling a single file with no deps, attempt to read its `.kti` file; if `Driver.isFresh`
returns `True` (source hash and dep hashes match), skip recompile entirely and return `ok=True`.
Write unit tests verifying the skip path and the recompile path.

## Current State

After S17-03, a `.kti` file is written after each successful compilation. `isFresh` exists as a
pure function but is never called within the compilation pipeline.

## Relationship to other stories

- **Depends on**: S17-03 (KTI must be written before freshness can be checked)
- **Blocks**: S17-08 (graph-wide freshness extends this per-file check)

## Goals

1. At the start of `compileFile`, read the existing `.kti` file (if any) using `Kti.readKtiFile`.
2. Compute the source hash of the current source text.
3. Call `Driver.isFresh(kti, sourceHash, emptyDepHashes)`.
4. If fresh, return `{ ok = True, diagnostics = [] }` immediately without re-lexing/parsing/etc.
5. If stale or no KTI exists, proceed with full compilation as before.

## Acceptance Criteria

- [x] `compileFile` skips recompilation when the source is unchanged and `.kti` is present.
- [x] `compileFile` recompiles when the source changes (KTI stale).
- [x] `compileFile` recompiles when no `.kti` exists.
- [x] `driver.test.ks` has tests for the skip path and recompile path.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — incremental compilation freshness

## Risks / Notes

- `Kti.readKtiFile` may return a `Result` or `Option`; handle the absent-KTI case gracefully.
- Source hashing must be consistent with S17-03 (same algorithm, same encoding).

## Impact analysis

- `stdlib/kestrel/tools/compiler/kti.ks`: export `sourceHash(s: String): String = pseudoHash(s)` so driver can compute the same hash used in KTI
- `stdlib/kestrel/tools/compiler/driver.ks`: after `readText(source)`, compute `val srcHash = Kti.sourceHash(source)`, read existing KTI, call `isFresh` — if fresh return success immediately; `moduleName` must be computed earlier in the function
- `stdlib/kestrel/tools/compiler/driver.test.ks`: test fresh skip path (compile twice, second call returns ok without re-running compilation) and stale path

## Tasks

- [x] Export `sourceHash` from `kti.ks`
- [x] In `compileFile`: compute `moduleName` and `srcHash` after reading source; attempt `readKtiFile`; if fresh return `{ok=True, diagnostics=[]}` immediately
- [x] Add test: compileFile returns ok on second call with same source (fresh path)
- [x] Add test: compileFile recompiles when source changes (stale KTI)
- [x] Run `./scripts/kestrel test`

## Tests to add

- `driver.test.ks`: fresh path — compile, then compile again unchanged, expect ok
- `driver.test.ks`: stale path — compile, change source, compile again, expect ok with recompilation

## Documentation and specs to update

- [x] No spec changes needed; mark reviewed

## Build notes

- 2026-04-26: Starting implementation.
