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
resolver, driver, CLI) will exist as Kestrel source files in `stdlib/kestrel/tools/compiler/`.
The TypeScript compiler can compile any Kestrel source; the question is whether the
Kestrel-written compiler, once compiled by TypeScript (Stage 0), produces correct output.

## Relationship to other stories

- **Depends on**: S14-01 through S14-12 (all compiler modules)
- **Blocks**: S14-14 (Stage-1 self-hosting)

## Goals

1. Create `scripts/bootstrap-stage0.sh` that:
   - Compiles all `stdlib/kestrel/tools/compiler/*.ks` sources using the TypeScript compiler.
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
