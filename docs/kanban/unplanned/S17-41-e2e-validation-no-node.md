# End-to-end validation without Node; CI gate and spec update

## Sequence: S17-41
## Tier: 9
## Former ID: S17-13 (then S17-23, then S17-39)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01 through S17-40

## Summary

Rename `compiler/` to verify the full test suite (1855+ tests) passes with Node unreachable.
Add a CI step that runs `mv compiler compiler_DISABLED && ./kestrel test` and must exit 0.
Restore `compiler/`. Update `docs/specs/11-bootstrap.md` and
`docs/specs/12-agent-enablement-and-knowledge.md` to reflect the JVM-only runtime path.

## Current State

The self-hosted typechecker has now closed the blocking declaration/typecheck gaps that were
preventing basic stdlib and test compilation, and the pipeline currently stays green with a
temporary self-hosted `main(String[])` shim plus targeted `E2E_SKIP_PENDING_CODEGEN` markers.
That means the project can compile enough code to keep CI moving, but it does NOT yet prove
real self-hosted runtime execution, real module startup, or the no-Node end state this story is
meant to validate.

## Relationship to other stories

- **Depends on**: S17-12 (CLI wired to driver) and the gap-closure stories S17-16..S17-22 which together remove every "Unsupported top-level declaration" or "Unsupported expression form" diagnostic raised by the self-hosted checker for stdlib inputs.
- **Depends on**: the execution tranche led by S17-25 and S17-37, which must replace the
  temporary `main` shim with real identifier/global-init/startup behavior.
- **Depends on**: the runtime-sensitive codegen stories needed to re-enable the currently
  skipped runtime-negative and positive E2E scenarios (notably S17-27 through S17-35, then
  S17-37 / S17-38 as required by the scenario set).
- **Blocks**: nothing — this is the final story in the epic.

## Goals

1. First remove the temporary execution workarounds by completing the S17-25 + S17-37 tranche
  and restoring real self-hosted startup/runtime behavior.
2. Re-enable the runtime-negative E2E scenarios currently skipped behind
  `E2E_SKIP_PENDING_CODEGEN` and make them pass under real execution.
3. Re-enable positive E2E scenarios in slices: core async/task scenarios first, then fs/process,
  then network/http/socket/web scenarios.
4. Restore strict failure in `scripts/test-all.sh` once `./kestrel test` is green without
  workaround handling.
5. Temporarily rename `compiler/` to `compiler_DISABLED/` and run `./kestrel test`.
6. Fix any remaining failures that reveal Node dependency paths.
7. Restore `compiler/`.
8. Add a CI gate (script or workflow step) that automates this validation.
9. Update `docs/specs/11-bootstrap.md` §1 and §2 to describe the JVM-only runtime path.
10. Update `docs/specs/12-agent-enablement-and-knowledge.md` to reflect that Node is no longer
  a runtime dependency.
11. Remove the `val next: Task<T> = ...; await next` workaround bindings in
   `stdlib/kestrel/tools/cli.ks` (`anyDepNewer` and `deleteFiles`) — deferred from S17-15
   because the bootstrap JAR at that time did not yet contain the fixed typecheck. By the
   time this story runs the JAR will have been rebuilt with the S17-15 fix included.

## Acceptance Criteria

- [ ] Runtime-negative E2E scenarios are no longer skipped and pass under real self-hosted
  execution.
- [ ] Positive E2E scenarios previously marked `E2E_SKIP_PENDING_CODEGEN` have been re-enabled
  in slices and pass without the temporary startup shim.
- [ ] `scripts/test-all.sh` is back to strict failure for `./kestrel test` (no warning downgrade).
- [ ] `./kestrel test` passes with `compiler/` renamed/absent.
- [ ] A CI gate script (`scripts/test-no-node.sh` or workflow step) exists and is documented.
- [ ] `docs/specs/11-bootstrap.md` reflects the JVM-only runtime path.
- [ ] `docs/specs/12-agent-enablement-and-knowledge.md` reflects the JVM-only runtime path.
- [ ] `cd compiler && npm run build && npm test` passes (TypeScript tests still pass with compiler present).
- [ ] `./scripts/kestrel test` passes.
- [ ] `stdlib/kestrel/tools/cli.ks` `anyDepNewer` and `deleteFiles` use direct `await f(rest)` calls (S17-15 workaround removed).

## Spec References

- `docs/specs/11-bootstrap.md` — bootstrap and self-hosted pipeline
- `docs/specs/12-agent-enablement-and-knowledge.md` — agent/tool knowledge

## Risks / Notes

- **Re-enable skipped positive E2E tests:** `tests/e2e/scenarios/positive/async-await-ktask-wiring.ks`
  carries a `// E2E_SKIP_PENDING_CODEGEN` marker and is skipped in `run-e2e.sh`. Remove the
  marker and the corresponding skip block in `run-e2e.sh` once S17-37 (`$init`/`main`
  emission) and its codegen prerequisites are complete and the positive test passes.
- **Re-enable skipped runtime-negative E2E tests:** `runtime_catch_no_match_rethrow.ks`,
  `runtime_divide_by_zero.ks`, `runtime_exit_one.ks`, `runtime_stack_overflow.ks`, and
  `uncaught_throw.ks` currently carry temporary `E2E_SKIP_PENDING_CODEGEN` markers because the
  stub `main` path does not execute them. Remove those markers as part of the same tranche that
  lands real startup/runtime execution.
- **Re-enable strict Kestrel unit-test gate in `scripts/test-all.sh`:** the current
  `./kestrel test || echo "WARNING..."` downgrade exists to tolerate temporary self-hosted
  codegen gaps (including stub `main` behavior). Restore strict failure (`|| exit 1`) once
  S17-37 and the dependent codegen implementation stories are complete and
  `./kestrel test` is green without workaround handling.
- Some E2E tests or fixtures may still invoke `node` indirectly (e.g. via `scripts/kestrel`
  Bash shim). Audit all test fixtures.
- The CI gate must restore `compiler/` after the test to avoid breaking the TypeScript build.
- The `compiler/dist/cli.js` path may still be needed for the bootstrap process (building the
  bootstrap JAR); document this clearly in the spec.
- **S17-15 deferred cleanup:** Before removing the `cli.ks` workaround bindings, confirm the
  bootstrap JAR in use was built after S17-15 landed (i.e. `./scripts/build-bootstrap-jar.sh`
  was re-run). The direct `await f(rest)` form will be rejected by any JAR that pre-dates the
  S17-15 typecheck fix.

