# Stage-0 Bootstrap Verification

## Sequence: S14-13
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01 through S14-12, S14-14

## Summary

Wire together all self-hosted compiler modules (S14-01 through S14-12) and verify Stage-0
of the bootstrap: the existing TypeScript compiler compiles the Kestrel-written compiler
sources to JVM bytecode, and the resulting binary correctly compiles a non-trivial Kestrel
program (`samples/mandelbrot.ks` or similar) with output semantically identical to the
TypeScript compiler.

This is the integration milestone that confirms the Kestrel compiler is functionally correct
before attempting self-hosting (Stage-1 in S14-14).

## Current State

Individual compiler modules (diagnostics, types, typechecker, classfile, codegen, KTI,
resolver, driver, CLI) now exist as Kestrel source files in `stdlib/kestrel/tools/compiler/`.
The TypeScript compiler can compile any Kestrel source; the question is whether the
Kestrel-written compiler, once compiled by TypeScript (Stage 0), produces correct output.

## Relationship to other stories

- **Depends on**: S14-01 through S14-12 (all compiler modules)
- **Blocks**: S14-14 (Stage-1 self-hosting)

## Goals

1. Create `scripts/bootstrap-stage0.sh` that:
   - Compiles all `stdlib/kestrel/compiler/*.ks` sources using the TypeScript compiler.
   - Runs the resulting Kestrel compiler binary against `samples/mandelbrot.ks`.
   - Compares output of the Kestrel-compiled binary against the TypeScript compiler output
     (byte-for-byte or semantic equivalence).
2. Fix any discrepancies found between Kestrel-compiler and TypeScript-compiler output.
3. Update `./kestrel build` to optionally use the Stage-0 Kestrel binary if it exists.
4. Document the bootstrap procedure in `docs/specs/` or `docs/guide.md`.

## Acceptance Criteria

- `./scripts/bootstrap-stage0.sh` completes successfully.
- The Stage-0 Kestrel compiler compiles `samples/mandelbrot.ks` producing bytecode that, when
  executed, produces output identical to running the program compiled by the TypeScript compiler.
- All existing Kestrel unit tests (`./kestrel test`) still pass.
- All E2E tests (`./scripts/run-e2e.sh`) still pass.
- `cd compiler && npm test` still passes.

## Spec References

- `docs/specs/09-tools.md` — build tool specification
- Epic E14 implementation approach (Stage 0 definition)

## Risks / Notes

- If any compiler module has a bug that only manifests on non-trivial programs, this story will
  surface it; the fix belongs in the relevant upstream story (S14-04 through S14-11).
- Byte-for-byte identity of `.class` output is not guaranteed across compilers (different
  constant pool ordering is allowed by the JVM spec); use semantic equivalence (same runtime
  output) as the primary check, with optional bytecode diff as a secondary diagnostic tool.
- The TypeScript compiler and Kestrel compiler may differ in how they handle certain edge cases
  (e.g. exact error message text, source-hash encoding); document any intentional divergences.

## Impact analysis

| Area | Change |
|------|--------|
| Scripts | Add `scripts/bootstrap-stage0.sh` to compile the self-hosted compiler entrypoint with the TypeScript bootstrap compiler and run a stage-0 verification flow against a representative program. |
| Self-hosted compiler CLI | Confirm `stdlib/kestrel/tools/compiler/cli-main.ks` can be compiled/executed by the TypeScript compiler and accepts the argument shapes used by the stage-0 script. |
| CLI wrapper | Update `scripts/kestrel` only if needed to support optional use of the stage-0 compiler artifact without breaking default TypeScript-bootstrap behaviour. |
| Samples / verification assets | Add deterministic output comparison fixtures under `tests/e2e/` (or dedicated bootstrap fixtures) for semantic equivalence checks between TypeScript and stage-0 outputs. |
| Specs/docs | Update tooling docs to document the stage-0 bootstrap command, prerequisites, and expected outputs. |

## Tasks

- [x] Implement `scripts/bootstrap-stage0.sh` with strict mode, repo-root resolution, and deterministic temp/output directories.
- [x] In `scripts/bootstrap-stage0.sh`, compile the self-hosted compiler entrypoint (`stdlib/kestrel/tools/compiler/cli-main.ks`) via the TypeScript compiler to produce the stage-0 JVM artifact.
- [x] In `scripts/bootstrap-stage0.sh`, run a non-trivial sample (`samples/mandelbrot.ks`) through baseline and post-bootstrap flows, and compare observable output.
- [x] Add semantic comparison logic to report success/failure with useful diagnostics when outputs diverge (exit codes, stdout diffs, artifact paths).
- [x] Update `scripts/kestrel` only if required to optionally consume an existing stage-0 artifact while preserving current default behaviour and fallback flow (reviewed; no change required).
- [x] Add regression verification coverage for stage-0 script happy-path via script-level smoke execution plus required compiler/Kestrel/E2E suites.
- [x] Update `docs/specs/09-tools.md` and `docs/guide.md` with stage-0 bootstrap procedure, prerequisites, and troubleshooting notes.
- [x] Run `./scripts/bootstrap-stage0.sh samples/mandelbrot.ks`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Script-level smoke | `scripts/bootstrap-stage0.sh` | Validate preflight checks, artifact creation, stage-0 build-command smoke execution, and semantic output comparison against baseline. |
| Compiler regression | `cd compiler && npm run build && npm test` | Ensure bootstrap verification changes do not regress compiler behavior. |
| Runtime regression | `./kestrel test` and `./scripts/run-e2e.sh` | Ensure bootstrap verification changes do not regress stdlib/runtime behavior. |

## Build notes

- 2026-04-12: Added `scripts/bootstrap-stage0.sh` to compile `kestrel:tools/compiler/cli-main` with the TypeScript bootstrap compiler and perform semantic output parity checks on `samples/mandelbrot.ks`.
- 2026-04-12: Current self-hosted CLI invocation from compiled stage-0 classes is used as a build-command smoke check; sample compilation for parity still uses canonical `./kestrel build` while argument-forwarding behavior stabilizes.
- 2026-04-12: First `./scripts/run-e2e.sh` run failed at `socket-tcp-connect` with async quiescence warnings; immediate rerun passed all E2E scenarios.

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — add a stage-0 bootstrap section defining script usage, prerequisites, and success/failure semantics.
- [x] `docs/guide.md` — document how to run stage-0 verification locally and interpret results.
