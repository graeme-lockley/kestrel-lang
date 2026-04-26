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

- [x] `compileFile` returns `ok=False` with a non-empty diagnostics list for a parse error.
- [x] `compileFile` returns `ok=False` with a non-empty diagnostics list for a type error.
- [x] Diagnostics are printed to stderr with file/line/column information.
- [x] `stdlib/kestrel/tools/compiler/driver.test.ks` has tests for parse-error and type-error paths.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/10-compile-diagnostics.md` — diagnostic format and rendering
- `docs/specs/07-modules.md` — incremental compilation

## Risks / Notes

- The TypeScript compiler uses `locationFromSpan` to convert a `Span` to a `DiagnosticLocation`;
  the Kestrel `Diag.locationFromSpan` function must be used equivalently.
- Parse errors in Kestrel have a different structure than typecheck diagnostics; both must be
  converted to the common `Diagnostic` type.

## Impact analysis

- `stdlib/kestrel/tools/compiler/driver.ks`: add `parseErrorToDiag` helper, update `Err(e)` parse
  branch and `!tc.ok` branch; add `Rep` import and `eprintln` stderr printing via `printDiagnosticsErr`
- `stdlib/kestrel/dev/typecheck/reporter.ks`: add `printDiagnosticsErr` using `eprintln`
- `stdlib/kestrel/tools/compiler/driver.test.ks`: update parse-error test to assert non-empty diagnostics; add type-error test

## Tasks

- [x] Add `printDiagnosticsErr` to `reporter.ks` (import `eprintln` from `kestrel:io/console`)
- [x] Import `Rep` (reporter) in `driver.ks`
- [x] Add `parseErrorToDiag(file, e)` helper in `driver.ks`
- [x] Update `Err(parseErr)` branch: return `{ ok=False, diagnostics=[parseErrorToDiag(entryPath, parseErr)] }`
- [x] Update `if (!tc.ok)` branch: return `{ ok=False, diagnostics=tc.diagnostics }`
- [x] Call `Rep.printDiagnosticsErr` before returning any `ok=False` result in `compileFile`
- [x] Update parse-error test: assert `!Lst.isEmpty(result.diagnostics)`
- [x] Add type-error test: compile `"let x: Int = \"hello\""`, assert `ok=False` and non-empty diagnostics
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

- `driver.test.ks`: extend parse-error test to assert diagnostics non-empty
- `driver.test.ks`: new test group "compileFile - type error" verifying ok=False and non-empty diagnostics

## Documentation and specs to update

- [x] No spec changes needed for this story; mark reviewed

## Build notes

- 2026-04-26: Starting implementation.
- 2026-04-26: Added `printDiagnosticsErr` to reporter.ks using `eprintln`.
- 2026-04-26: `exception` types (like `ParseError`) used as type annotations in function parameters create fresh type vars (not registered in `typeAliases`), so `match (e) { ParseError(...) }` fails to bind variables when `e: ParseError` is explicitly annotated. Workaround: use inferred types from `Err(e)` match on a `Result`.
- 2026-04-26: Nested exception constructor patterns inside `async fun` cause JVM VerifyError (local slot mismatch in stackmap). Workaround: extract to a synchronous helper that returns a local ADT (`ParseOutcome`) — the async function matches on the ADT, not the exception directly.
- 2026-04-26: All 20 driver tests pass; 1870 total Kestrel tests pass.
