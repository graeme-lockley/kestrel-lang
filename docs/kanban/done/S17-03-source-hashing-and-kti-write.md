# Source hashing and KTI write after successful compile

## Sequence: S17-03
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Compute SHA-256 source hash, call `Kti.buildKtiV4`, call `Kti.writeKtiFile` to persist the
`.kti` cache file alongside `.class` output. No freshness check yet — always rewrite.

## Current State

After S17-02, `compileFile` produces `.class` files and surfaces diagnostics. No KTI file is
written yet. The `isFresh` function exists but is never called.

## Relationship to other stories

- **Depends on**: S17-02 (full pipeline with diagnostics needed first)
- **Blocks**: S17-04 (freshness check reads the KTI file written here)

## Goals

1. After successful compilation (no error diagnostics), compute SHA-256 hash of source text.
2. Call `Kti.buildKtiV4` to build the KTI record from the typecheck result, source hash, and
   an empty dep-hashes dict (multi-module deps added in S17-06+).
3. Call `Kti.writeKtiFile` to persist the KTI alongside the `.class` output if `opts.writeKti`
   is `True`.
4. Only write KTI when compilation succeeded (no error diagnostics).

## Acceptance Criteria

- [x] A `.kti` file is written to `outDir` after successful single-file compilation.
- [x] No `.kti` file is written when compilation fails (parse/type errors).
- [x] `opts.writeKti = False` suppresses KTI writing.
- [x] `driver.test.ks` verifies the KTI write path.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — KTI format and freshness
- `docs/specs/kti-format.md` — KTI file structure

## Risks / Notes

- SHA-256 hashing must be available in Kestrel — check `kestrel:data/string` or `kestrel:io/fs`
  for a hash function, or implement one using the JVM `MessageDigest` primitive.
- `Kti.buildKtiV4` requires the typecheck export snapshot; verify the Kestrel typecheck API
  returns an equivalent structure.
- The KTI file path: typically `<outDir>/<ModuleName>.kti` — verify what path convention
  the TypeScript compiler uses and replicate it.

## Impact analysis

- `stdlib/kestrel/tools/compiler/driver.ks`: after `writeAllClasses` succeeds and `opts.writeKti = True`, call `Kti.buildKtiV4(prog, tc.exports.items, source, Dict.emptyStringDict())` then `Kti.writeKtiFile("${opts.outDir}/${moduleName}.kti", kti)`; `source` must be threaded through from `Fs.readText`; `prog` and `tc` also available in scope
- `stdlib/kestrel/tools/compiler/driver.test.ks`: test that `.kti` file is created when `writeKti=True`; test that it is NOT created when `writeKti=False`; test that it is NOT created on failure

## Tasks

- [x] Thread `source` through to the success path in `compileFile`
- [x] After `writeAllClasses` succeeds, conditionally write KTI: if `opts.writeKti` is True, `val kti = Kti.buildKtiV4(prog, tc.exports.items, source, Dict.emptyStringDict()); await Kti.writeKtiFile("${opts.outDir}/${moduleName}.kti", kti)`
- [x] Return `ok=True` if KTI write succeeds (or is skipped); `ok=False` with file error if KTI write fails
- [x] Add test: writeKti=True writes a `.kti` file (assert file exists after compile)
- [x] Add test: writeKti=False does not write `.kti` file
- [x] Run `./scripts/kestrel test`

## Tests to add

- `driver.test.ks`: test that KTI file is written when `writeKti=True`
- `driver.test.ks`: test that KTI file is NOT written when `writeKti=False`

## Documentation and specs to update

- [x] No spec changes needed for this story; mark reviewed

## Build notes

- 2026-04-26: Starting implementation.
