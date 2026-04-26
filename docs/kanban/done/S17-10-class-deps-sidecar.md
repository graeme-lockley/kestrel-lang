# .class.deps sidecar file writing

## Sequence: S17-10
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-11, S17-12, S17-13

## Summary

After compiling a module, write `<ClassName>.class.deps` listing the absolute paths of all
direct and transitive source dependencies. This file is used by `cli.ks` for mtime-based
staleness checks (legacy freshness path). Format: one absolute path per line.

## Current State

After S17-09, the driver compiles multi-module programs with URL support. But no `.class.deps`
sidecar files are written. The Bash shim and legacy CLI depend on these files to determine
whether to re-run the Kestrel compiler.

## Relationship to other stories

- **Depends on**: S17-09 (full graph with URL deps available)
- **Blocks**: S17-12 (wire cli.ks; cli uses .class.deps for staleness)

## Goals

1. After writing `.class` files for a module, also write a `<ClassName>.class.deps` file to
   `outDir` containing the absolute paths of all direct and transitive source dependencies of
   that module (in the order they appear in the topological sort).
2. Include the entry file itself in the deps list.
3. Format: one absolute path per line, UTF-8 encoded, newline-terminated.

## Acceptance Criteria

- [x] `<ClassName>.class.deps` is written to `outDir` after compilation.
- [x] The file contains the absolute paths of all transitive source deps (including stdlib).
- [x] `driver.test.ks` verifies the sidecar file content for a two-module program.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — class.deps sidecar use by CLI

## Risks / Notes

- Only write `.class.deps` for modules that were actually compiled (not for fresh/skipped
  modules where the existing sidecar is still valid).
- Absolute path canonicalization: ensure symlinks are resolved consistently.

---

## Impact analysis

### Files changed

| File | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/driver.ks` | Add `processedOrder: List<String>` to `GraphState`; change `ModuleCompileResult` to carry a `wasCompiled: Bool` flag; add `writeDepsFile` async helper; wire into `compileGraph`; init `processedOrder` in `compileFile` |
| `stdlib/kestrel/tools/compiler/driver.test.ks` | Add test group verifying `.class.deps` content for two-module program |
| `docs/specs/11-bootstrap.md` | Document `.class.deps` file format (one path per line, UTF-8, newline-terminated, transitive deps + self) |

### No change needed

- `driver-kti-loading.test.ks` — does not interact with `ModuleCompileResult` internals
- `cli-main.ks` — no CLI surface change

## Tasks

- [x] Add `processedOrder: List<String>` to `GraphState` in `driver.ks`
- [x] Change `ModuleCompileResult` to `ModuleCompileOk(String, Bool)` (ktiText, wasCompiled)
- [x] Update `compileOneModule` — fresh path returns `ModuleCompileOk(content, False)`, compiled path returns `ModuleCompileOk(content, True)`
- [x] Add `writeDepsFile` async helper: writes `<outDir>/<className>.class.deps` with all transitive deps + self (one path per line, UTF-8, newline-terminated)
- [x] Update `compileGraph` to record `startLen` before `compileDepsInOrder`, then after `compileOneModule` succeeds with `wasCompiled=True`, compute transitive dep list and call `writeDepsFile`; always update `processedOrder` with `p` after success
- [x] Update `compileFile` to initialize `processedOrder = []` in the initial `GraphState`
- [x] Add test group `"compileFile — class.deps sidecar for two-module program"` in `driver.test.ks`
- [x] Update `docs/specs/11-bootstrap.md` to describe `.class.deps` format

## Tests to add

In `driver.test.ks`:
- Test group "compileFile — class.deps sidecar for two-module program":
  - Write `dep.ks` (exports a function) and `main.ks` (imports dep, exports another)
  - Compile with `writeKti=True`
  - Assert `dep.class.deps` content = `dep.ks path\n`
  - Assert `main.class.deps` content = `dep.ks path\nmain.ks path\n`

## Documentation and specs to update

- `docs/specs/11-bootstrap.md` §2.1 — expand `.class.deps` description: format is one absolute source path per line, UTF-8 encoded, newline-terminated; contains all transitive source deps in DFS post-order, with the module itself last

## Build notes

- Started implementation.
- Added `processedOrder: List<String>` to `GraphState` to track DFS post-order of processed modules; used to compute each module's transitive dep list for the `.class.deps` file.
- Changed `ModuleCompileResult` to `ModuleCompileOk(String, Bool)` to carry a `wasCompiled` flag distinguishing actual compilation from fresh/incremental skip.
- `writeDepsFile` / `writeDepsFileIfCompiled` helpers keep `compileGraph` from getting too many async locals, consistent with the S17-09 extraction pattern.
- All 1928 Kestrel tests and 440 compiler tests pass.
