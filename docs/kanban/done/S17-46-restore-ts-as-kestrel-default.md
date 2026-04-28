# Restore TS compiler as the default for `./kestrel`

## Sequence: S17-46
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-45, S17-47, S17-48, S17-50, S17-49

## Summary

Revert the user-visible effect of S17-12: make `./kestrel run` (and all other `./kestrel`
commands that compile `.ks` files) call the TypeScript compiler subprocess instead of the
self-hosted `Driver.compileFile` in-process. Preserve the driver code so the self path
(S17-47) can reuse it. Restore the unit tests that were weakened or TEMP-stubbed to accommodate
the self-hosted compiler, and remove the `E2E_SKIP_PENDING_CODEGEN` markers that were inserted
because the self-hosted compiler could not handle those scenarios.

## Current State

- `stdlib/kestrel/tools/cli.ks` `compileScript` calls `Driver.compileFile` in-process (S17-12
  wiring). Every `./kestrel run` therefore exercises the self-hosted compiler.
- `tests/unit/union_intersection.test.ks` lines 5–11 contain a TEMP(S17-44) stub that replaces
  the real `is`-narrowing scenario with a passing no-op.
- `tests/unit/functions.test.ks` line 130 has a TEMP comment suppressing block-local mutual
  recursion (which the self-hosted typechecker does not support).
- ~20 `tests/e2e/scenarios/{positive,negative}/*.ks` files carry a leading
  `// E2E_SKIP_PENDING_CODEGEN` comment causing `scripts/run-e2e.sh` to skip them.
- `scripts/run-e2e.sh` lines 62, 121, 170 contain skip logic for the marker.

## Relationship to other stories

- **Depends on**: S17-45 (new TS cache path `~/.kestrel/ts/` must be in place)
- **Blocks**: S17-47 (self path must be clearly separated before adding `kestrel-self` script)

## Goals

1. `cli.ks` `compileScript` detects whether it is running under the TS path or the self path
   (via an env var set by the respective launch script) and routes accordingly:
   - TS path → calls `--allow-ts-compiler __ts-compile` subprocess (as before S17-12).
   - Self path → calls `Driver.compileFile` in-process (S17-12 wiring, preserved).
2. Restore `tests/unit/union_intersection.test.ks` to its original `is`-narrowing scenario.
3. Restore `tests/unit/functions.test.ks` block-local mutual recursion test.
4. Remove `// E2E_SKIP_PENDING_CODEGEN` from all ~20 affected e2e scenario files.
5. Remove the `E2E_SKIP_PENDING_CODEGEN` skip logic from `scripts/run-e2e.sh`.
6. All TS compiler tests (`cd compiler && npm test`) and `./scripts/kestrel test` pass.
7. `./scripts/run-e2e.sh` passes with no skipped scenarios (on account of the marker).

## Acceptance Criteria

- [x] `./kestrel run hello.ks` compiles via the TS compiler subprocess.
- [x] All `tests/unit/` tests pass under `./kestrel test` with no TEMP stubs.
- [x] `./scripts/run-e2e.sh` runs the previously-skipped scenarios and they all pass.
- [x] The `E2E_SKIP_PENDING_CODEGEN` marker and its skip logic are fully removed from the
      codebase.
- [x] `cd compiler && npm run build && npm test` passes.

## Spec References

- `docs/specs/09-tools.md` — compilation path description
- `docs/specs/11-bootstrap.md` — bootstrap flow

## Risks / Notes

- The routing mechanism in `cli.ks` should use an env var (`KESTREL_COMPILER_PATH=ts|self`
  or `KESTREL_SELF=1`) set by the respective launch script (`scripts/kestrel` sets TS,
  `scripts/kestrel-self` sets self). This avoids any runtime class inspection.
- Care must be taken that the self path continues to call `Driver.compileFile` in-process
  (not break it); the TS path is what reverts, not the self path code.
- The restored `is`-narrowing and mutual-recursion tests are run by `./kestrel test` (TS
  compiler); they do NOT need to pass under `./kestrel-self` until S17-50 baseline sweep.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/cli.ks` | Restore `compileScript` (TS subprocess) alongside `compileWithDriver`; add routing function `compile` that checks `KESTREL_SELF` env var and routes to the appropriate implementation; update all call sites |
| `tests/unit/union_intersection.test.ks` | Restore original `is`-narrowing test (remove TEMP stub) |
| `tests/unit/functions.test.ks` | Restore block-local mutual recursion test lines (remove TEMP comment) |
| `tests/e2e/scenarios/positive/*.ks` (20 files) | Remove `// E2E_SKIP_PENDING_CODEGEN` leading comment line |
| `tests/e2e/scenarios/negative/*.ks` (5 files) | Remove `// E2E_SKIP_PENDING_CODEGEN` leading comment line |
| `scripts/run-e2e.sh` | Remove E2E_SKIP_PENDING_CODEGEN skip logic (lines 62-64, 121-124, 170 condition) |

## Tasks

- [x] `stdlib/kestrel/tools/cli.ks`: restore `compileScript` (TS subprocess) function
      alongside `compileWithDriver`; add `compile` routing function checking `KESTREL_SELF=1`;
      update all `compileWithDriver` call sites in `cmdRun`, `cmdDis`, `cmdBuild`, `cmdTest`,
      `cmdFmt`, `cmdDoc`, and `cmdTsCompile` to use `compile` (or the appropriate direct call)
- [x] `tests/unit/union_intersection.test.ks`: restore original `is`-narrowing scenario
      (remove lines 4-12 TEMP stub, restore `fun takeU` + two `eq` assertions)
- [x] `tests/unit/functions.test.ks`: restore block-local mutual recursion test
      (uncomment the two `isTrue` lines, remove TEMP comment)
- [x] Remove `// E2E_SKIP_PENDING_CODEGEN` first-line comment from all 29 affected e2e files
- [x] `scripts/run-e2e.sh`: remove E2E_SKIP_PENDING_CODEGEN skip blocks at lines 62-64,
      121-124; remove E2E_SKIP_PENDING_CODEGEN guard from the CLI smoke check at line 170
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

No new test files needed — this story restores existing tests that were TEMP-disabled.

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — note that `KESTREL_SELF=1` env var selects the self-hosted
      compiler path in `cli.ks`; document the `compileScript` (TS subprocess) vs
      `compileWithDriver` (in-process) routing

## Build notes

- **2025-04-28**: Implemented routing via `KESTREL_SELF=1` env var in `cli.ks`. `compileScript`
  calls the TS compiler subprocess via `node compiler/dist/cli.js`; `compile()` checks the env
  var and routes to either `compileScript` or `compileWithDriver`.
- **scripts/kestrel updated**: Now looks for `Cli.class` in `JVM_CACHE` first (TS-compiled),
  then `SELF_CACHE`; classpath is `MAVEN_RUNTIME_JAR:JVM_CACHE:SELF_CACHE`.
- **Stale bootstrap classes**: After clearing old `~/.kestrel/ts/` (previously copied from
  `~/.kestrel/jvm/` as bootstrap-compiled classes without `$init()` methods), fresh
  recompilation with the TS compiler produces classes with proper `$init()` methods. The old
  bootstrap-compiled classes lacked `$init()` because they were built with a pre-`$init` codegen.
- **unify.ts fix**: Added union/inter case to the symmetric `unify` function. Without it,
  block-local functions with union-typed params failed to type-check.
- **typecheck.ks fixes**: Added `TDExternFun` to named imports (line 24) and added missing
  semicolon after `maybeExportBinding` call (line 911).
- **typecheck.test.ks**: Fixed `extern fun` tests to use `jvm("...")` syntax (parser now
  requires `= jvm("descriptor")` not `= "descriptor"`). Generic type test updated to check
  `startsWith("forall 1 vars.")` since var IDs are internal implementation detail.
- **runtime-stdlib.test.ts**: Updated bootstrap test to use both empty `KESTREL_TS_CACHE` and
  `KESTREL_SELF_CACHE` to trigger the "no artifacts" error path.
