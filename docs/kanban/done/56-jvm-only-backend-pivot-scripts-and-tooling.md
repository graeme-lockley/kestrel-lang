# JVM-Only Backend Pivot: Scripts and Tooling

## Sequence: 56
## Tier: 8
## Former ID: (none)

## Summary

Update CLI scripts, build helpers, and test automation to remove Zig VM build/test/run paths and establish JVM-only developer workflows as the sole supported path.

## Current State

- `scripts/kestrel` (734 lines) contains ~22 Zig/VM references including `zig build`, VM test targets, and dual-backend dispatch logic.
- `scripts/test-all.sh` invokes `cd vm && zig build test` as a required step and runs both VM and JVM unit tests separately.
- `scripts/build-cli.sh` references Zig build paths.
- `scripts/run-e2e.sh` may reference VM execution paths.
- `scripts/jvm-smoke.mjs` exists for JVM-specific smoke testing.

## Relationship to other stories

- **Depends on** 55 (roadmap/doc alignment) so expectations are documented before tooling changes.
- **Precedes** 57 (Zig VM code removal) — scripts must stop requiring `vm/` before the directory is deleted.
- **Independent of** 58 (specs alignment).

## Goals

- All developer-facing scripts work without Zig installed or `vm/` present.
- `./scripts/kestrel test` runs JVM-only tests.
- `./scripts/test-all.sh` runs compiler tests, E2E, and JVM Kestrel tests — no Zig step.
- `./scripts/kestrel build` builds the compiler and JVM runtime only.
- `./scripts/kestrel run` executes via JVM only.

## Acceptance Criteria

- [x] `scripts/kestrel` no longer invokes or references Zig VM build/test/run commands.
- [x] `scripts/test-all.sh` no longer invokes `cd vm && zig build test`; runs JVM-only test paths.
- [x] `scripts/build-cli.sh` no longer references Zig build paths.
- [x] `scripts/run-e2e.sh` uses JVM execution only (if it previously supported VM).
- [x] `--target vm` / `--target jvm` flags removed or `--target jvm` becomes the implicit default with no alternative.
- [x] `./scripts/kestrel test` passes without Zig installed.
- [x] `./scripts/test-all.sh` passes end-to-end without Zig installed.
- [x] `kestrel test-both` command removed or repurposed (no second backend to compare).
- [x] `kestrel dis` works with JVM-only workflow (or is documented as JVM-oriented).

## Spec References

- `docs/specs/09-tools.md` — CLI command documentation (spec updates handled by **58**, but script behaviour must be consistent).

## Risks / Notes

- Must be careful not to break working JVM paths while removing VM paths.
- Run full test suite after changes to confirm no regressions.
- If `kestrel test-both` is in active use by other stories or tests, document removal clearly.

## Impact analysis

| Area | Files / subsystems | Change | Risk |
|------|-------------------|--------|------|
| **CLI** | `scripts/kestrel` | Remove VM dispatch, `--target` flag logic, `test-both`, `zig build` calls | Medium — largest file, most logic |
| **Test runner** | `scripts/test-all.sh` | Remove VM test step; simplify to compiler + JVM + E2E | Low |
| **Build** | `scripts/build-cli.sh` | Remove Zig build references | Low |
| **E2E** | `scripts/run-e2e.sh` | Ensure JVM-only execution | Low |
| **Smoke** | `scripts/jvm-smoke.mjs` | Keep or rename (already JVM-specific) | Low |

## Tasks

- [x] Audit `scripts/kestrel` for all Zig/VM references; list specific functions and flag logic to remove.
- [x] Update `scripts/kestrel` to remove VM build/test/run/dis paths and `--target` dispatch.
- [x] Update `scripts/test-all.sh` to remove `cd vm && zig build test` step and `kestrel test` VM invocation.
- [x] Update `scripts/build-cli.sh` to remove Zig build references.
- [x] Update `scripts/run-e2e.sh` to ensure JVM-only execution.
- [x] Remove or repurpose `kestrel test-both` command.
- [x] Run `./scripts/kestrel test` and confirm pass.
- [x] Run `./scripts/test-all.sh` and confirm pass.
- [x] Run `./scripts/run-e2e.sh` and confirm pass.

## Tests to add

- No new test files — this story verifies existing tests pass under JVM-only tooling.
- Verification: `cd compiler && npm test`, `./scripts/kestrel test`, `./scripts/test-all.sh`, `./scripts/run-e2e.sh`.

## Documentation and specs to update

- None directly — doc updates are in **55**, spec updates in **58**. Script comments should reflect JVM-only intent.

## Build notes

- 2026-04-03: Moved story to `doing/` and converted `scripts/kestrel`, `scripts/test-all.sh`, `scripts/build-cli.sh`, and `scripts/run-e2e.sh` to JVM-only workflows (removed Zig/VM paths and `test-both`).
- 2026-04-03: Verified `./scripts/run-e2e.sh` passes with JVM-only execution.
- 2026-04-03: Resolved the remaining JVM codegen/runtime failures uncovered by the JVM-only scripts so `./scripts/kestrel test` and `./scripts/test-all.sh` now pass end-to-end.
- 2026-04-03: Moved story to `done/` after rebuilding the JVM runtime/compiler and verifying the full suite from a clean JVM cache.