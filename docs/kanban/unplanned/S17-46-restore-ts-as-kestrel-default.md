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

- [ ] `./kestrel run hello.ks` compiles via the TS compiler subprocess.
- [ ] All `tests/unit/` tests pass under `./kestrel test` with no TEMP stubs.
- [ ] `./scripts/run-e2e.sh` runs the previously-skipped scenarios and they all pass.
- [ ] The `E2E_SKIP_PENDING_CODEGEN` marker and its skip logic are fully removed from the
      codebase.
- [ ] `cd compiler && npm run build && npm test` passes.

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
