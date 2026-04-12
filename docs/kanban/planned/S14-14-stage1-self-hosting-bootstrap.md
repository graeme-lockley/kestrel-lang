# Stage-1 Self-Hosting Bootstrap

## Sequence: S14-14
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01 through S14-13

## Summary

Achieve full self-hosting: use the Stage-0 Kestrel binary (produced in S14-13) to recompile
the Kestrel compiler sources, verify that the Stage-1 output is correct (compiles non-trivial
programs, matches Stage-0 output), and switch `./kestrel build` to invoke the Stage-1
self-hosted binary as the primary compiler. The TypeScript compiler becomes a documented
emergency fallback only.

## Current State

After S14-13, a Stage-0 Kestrel compiler binary exists and is known to correctly compile
most Kestrel programs. Stage-1 requires using that binary to re-compile its own source,
producing a new binary whose outputs should be semantically equivalent to Stage-0.

At present, Stage-0 verification is wiring-complete but still relies on the canonical
`./kestrel build` path for sample compilation in semantic parity checks. Stage-1 planning must
explicitly account for this dependency before switching the default build path.

## Relationship to other stories

- **Depends on**: S14-13 (Stage-0 must be verified before Stage-1)
- **Final story** in E14

## Goals

1. Create `scripts/bootstrap-stage1.sh` that:
   - Uses the Stage-0 binary to compile all `stdlib/kestrel/compiler/*.ks` sources.
   - Runs Stage-1 binary against `samples/mandelbrot.ks`.
   - Diffs Stage-1 output against Stage-0 output (semantic equivalence check).
2. Optionally run Stage-2 (Stage-1 compiles itself; confirm Stage-2 = Stage-1).
3. Update `./kestrel build` to use the Stage-1 binary as the default compiler.
4. Update `scripts/kestrel` to no longer require Node.js / the TypeScript compiler in the
   normal (non-fallback) build path.
5. Archive or document the TypeScript compiler as an emergency fallback in `AGENTS.md` and
   `docs/guide.md`.
6. Update `docs/specs/` — especially `09-tools.md` — to reflect the self-hosted build topology.

## Acceptance Criteria

- `./scripts/bootstrap-stage1.sh` succeeds.
- The Stage-1 compiler compiles `samples/mandelbrot.ks` with output identical to Stage-0.
- Running `./kestrel build hello.ks` no longer requires Node.js (unless the fallback is
  explicitly engaged).
- All Kestrel unit tests (`./kestrel test`) pass.
- All E2E tests (`./scripts/run-e2e.sh`) pass.
- All compiler conformance tests (`cd compiler && npm test`) pass when run against Stage-1
  compiled test fixtures.
- `docs/specs/09-tools.md` and `AGENTS.md` reflect the new build topology.

## Spec References

- Epic E14 completion criteria
- `docs/specs/09-tools.md`
- `AGENTS.md`

## Risks / Notes

- If Stage-1 output differs from Stage-0, the bug must be traced to a specific compiler
  module; the fix belongs in the relevant upstream story.
- Self-hosting requires that the Kestrel compiler can parse, typecheck, and codegen its own
  source, including any language features it uses internally. Any features not handled by the
  Kestrel implementation will block Stage-1.
- Stage-2 reproducibility (Stage-1 binary = Stage-2 binary bit-for-bit) is an optional
  quality check and not required for epic completion.
- After self-hosting, the TypeScript compiler should not be removed immediately — keep it as a
  documented fallback for at least one release cycle.

## Impact analysis

| Area | Change |
|------|--------|
| Scripts | Add `scripts/bootstrap-stage1.sh` to perform Stage-1 bootstrap checks (Stage-0 artifact -> Stage-1 artifact -> semantic parity validation). |
| CLI wrapper | Potentially update `scripts/kestrel` default build path to prefer Stage-1 artifact, retaining an explicit TypeScript fallback switch. |
| Self-hosted compiler modules | Validate that `kestrel:tools/compiler/cli-main` and `kestrel:tools/compiler/driver` can execute the Stage-1 flow without delegating core compile work back to TypeScript in the normal path. |
| Tooling docs/specs | Update `docs/specs/09-tools.md`, `docs/guide.md`, and `AGENTS.md` with Stage-1 topology and fallback policy. |
| Verification suites | Add bootstrap-stage1 verification plus full compiler/Kestrel/E2E regression gates before changing defaults. |

## Tasks

- [ ] Implement `scripts/bootstrap-stage1.sh` with strict mode, deterministic artifact directories, and explicit Stage-0/Stage-1 output reporting.
- [ ] In `scripts/bootstrap-stage1.sh`, consume Stage-0 artifacts from `scripts/bootstrap-stage0.sh` (or recreate them) and generate Stage-1 artifacts through the self-hosted path.
- [ ] Add Stage-1 semantic parity checks on `samples/mandelbrot.ks` output versus Stage-0 baseline.
- [ ] Add clear failure diagnostics when Stage-1 execution still delegates required compile steps to TypeScript in normal mode.
- [ ] Update `scripts/kestrel` to default to Stage-1 only if bootstrap verification demonstrates that Node/TypeScript are no longer required in the normal build path; otherwise preserve fallback topology and document the blocker.
- [ ] Update `docs/specs/09-tools.md`, `docs/guide.md`, and `AGENTS.md` with Stage-1 status, default path policy, and fallback instructions.
- [ ] Run `./scripts/bootstrap-stage1.sh`.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./kestrel test`.
- [ ] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Script-level integration | `scripts/bootstrap-stage1.sh` | Validate Stage-0 -> Stage-1 artifact generation and parity checks with actionable diagnostics. |
| Compiler regression | `cd compiler && npm run build && npm test` | Ensure Stage-1 bootstrap changes do not regress TypeScript compiler behavior during transition. |
| Runtime regression | `./kestrel test` and `./scripts/run-e2e.sh` | Ensure Stage-1 bootstrap changes do not regress runtime/stdlib behavior. |

## Documentation and specs to update

- [ ] `docs/specs/09-tools.md` — update build topology section for Stage-1 default or explicitly documented fallback status.
- [ ] `docs/guide.md` — add Stage-1 bootstrap instructions and troubleshooting.
- [ ] `AGENTS.md` — update project build/testing guidance to reflect Stage-1 status and fallback expectations.
