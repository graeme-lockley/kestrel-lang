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
