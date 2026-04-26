# Diagnostic propagation through CompileResult

## Sequence: S17-02
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Surface parse errors and typecheck `Diagnostic` list through `CompileResult.diagnostics` and
render them to stderr in the same format as the TypeScript compiler. `compileFile` returns
`ok=False` with populated diagnostics for invalid source.

## Current State

After S17-01, `compileFile` returns `ok=False` when parsing fails but with an empty diagnostics
list. Typecheck diagnostics are also not surfaced. The TypeScript compiler renders diagnostics
with file/line/column information to stderr.

## Relationship to other stories

- **Depends on**: S17-01 (pipeline must exist before diagnostics can be added)
- **Blocks**: S17-03 (KTI write should only happen if no diagnostics)

## Goals

1. When `parseFromList` returns `Err`, convert the parse error to a `Diagnostic` and include it
   in `CompileResult.diagnostics`.
2. When `typecheck` returns diagnostics (errors), propagate them through `CompileResult.diagnostics`.
3. `compileFile` returns `ok=False` when there are any error-severity diagnostics.
4. Print diagnostics to stderr in the same format as the TypeScript compiler output.

## Acceptance Criteria

- [ ] `compileFile` returns `ok=False` with a non-empty diagnostics list for a parse error.
- [ ] `compileFile` returns `ok=False` with a non-empty diagnostics list for a type error.
- [ ] Diagnostics are printed to stderr with file/line/column information.
- [ ] `stdlib/kestrel/tools/compiler/driver.test.ks` has tests for parse-error and type-error paths.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/10-compile-diagnostics.md` — diagnostic format and rendering
- `docs/specs/07-modules.md` — incremental compilation

## Risks / Notes

- The TypeScript compiler uses `locationFromSpan` to convert a `Span` to a `DiagnosticLocation`;
  the Kestrel `Diag.locationFromSpan` function must be used equivalently.
- Parse errors in Kestrel have a different structure than typecheck diagnostics; both must be
  converted to the common `Diagnostic` type.
