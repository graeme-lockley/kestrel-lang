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

- [ ] `compileFile` skips recompilation when the source is unchanged and `.kti` is present.
- [ ] `compileFile` recompiles when the source changes (KTI stale).
- [ ] `compileFile` recompiles when no `.kti` exists.
- [ ] `driver.test.ks` has tests for the skip path and recompile path.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — incremental compilation freshness

## Risks / Notes

- `Kti.readKtiFile` may return a `Result` or `Option`; handle the absent-KTI case gracefully.
- Source hashing must be consistent with S17-03 (same algorithm, same encoding).
