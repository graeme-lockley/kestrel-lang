# Compiler Diagnostics Module

## Sequence: S14-01
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the TypeScript compiler diagnostics types and reporter to a new Kestrel module
`kestrel:tools/compiler/diagnostics`. This is the foundational data layer that all other
self-hosted compiler modules depend on for emitting structured error messages.

Covers `compiler/src/diagnostics/types.ts` (~98 lines) and
`compiler/src/diagnostics/reporter.ts` (~159 lines).

## Current State

The TypeScript compiler has a well-defined diagnostics system in
`compiler/src/diagnostics/`:
- `types.ts`: `Diagnostic` record, `DiagnosticCode` constants (`CODES`), `Severity` enum,
  `Span` and `Location` types, `locationFromSpan` and `locationFileOnly` helpers.
- `reporter.ts`: `DiagnosticReporter` that collects diagnostics and exposes methods to
  add/query them, plus terminal pretty-printing (`printDiagnostics`).

There is no `stdlib/kestrel/tools/compiler/` directory yet. This story creates it.

## Relationship to other stories

- **Blocks**: all other S14 compiler stories — they all import `Diagnostic` and related types.
- **Depends on**: nothing beyond the existing Kestrel stdlib (string formatting, list, option).

## Goals

1. Create `stdlib/kestrel/tools/compiler/diagnostics.ks` with:
   - `Severity` ADT: `Error | Warning | Info | Hint`
   - `Span` record: `{ file: String, startOffset: Int, endOffset: Int, startLine: Int, startColumn: Int }`
   - `Location` record that mirrors the TS type (file, line, column, endLine, endColumn)
   - `Diagnostic` record: `{ code: String, message: String, severity: Severity, location: Location, relatedLocations: List<Location>, suggestion: Option<String> }`
   - `CODES` value exporting all diagnostic code constants (matching the TypeScript `CODES` object)
   - `locationFromSpan` and `locationFileOnly` helpers
2. Create `stdlib/kestrel/tools/compiler/reporter.ks` with:
   - `Reporter` opaque type wrapping a mutable list
   - `newReporter(): Reporter`
   - `report(r: Reporter, d: Diagnostic): Unit`
   - `hasErrors(r: Reporter): Bool`
   - `diagnostics(r: Reporter): List<Diagnostic>`
   - `printDiagnostics(ds: List<Diagnostic>, source: String): Unit` (terminal pretty-printer)

## Acceptance Criteria

- `stdlib/kestrel/tools/compiler/diagnostics.ks` and `reporter.ks` compile without errors.
- A test file `stdlib/kestrel/tools/compiler/diagnostics.test.ks` covers:
  - constructing a `Diagnostic` with each `Severity`
  - `locationFromSpan` produces the expected `Location`
  - `Reporter` accumulates diagnostics and `hasErrors` reflects them
- `./kestrel test stdlib/kestrel/tools/compiler/diagnostics.test.ks` passes.
- `cd compiler && npm test` still passes.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib | Add new module `stdlib/kestrel/tools/compiler/diagnostics.ks` containing compiler diagnostic records, severity ADT, code constants, and location helpers. |
| Stdlib | Add new module `stdlib/kestrel/tools/compiler/reporter.ks` containing a mutable reporter accumulator and human-readable printer entrypoint. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/diagnostics.test.ks` to verify constructors, helper functions, and reporter accumulation behaviour. |
| Compiler (TS reference parity) | Reference-only parity check against `compiler/src/diagnostics/types.ts` and `compiler/src/diagnostics/reporter.ts` to keep code names and field shape aligned during bootstrap transition. |
| Specs/docs | Update diagnostics spec section to mention self-hosted mirror module path and parity expectations for diagnostic code strings. |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/` directory and add `diagnostics.ks` with exported `Severity`, `SourceLocation`, `Diagnostic`, `RelatedLocation`, and `CODES` values.
- [x] Implement `lineColumnFromOffset`, `locationFromSpan`, and `locationFileOnly` in `stdlib/kestrel/tools/compiler/diagnostics.ks`.
- [x] Add `stdlib/kestrel/tools/compiler/reporter.ks` with `Reporter` state, `newReporter`, `report`, `hasErrors`, and `diagnostics` functions.
- [x] Implement `printDiagnostics(ds, source)` in `stdlib/kestrel/tools/compiler/reporter.ks` with basic single-line caret rendering.
- [x] Add `stdlib/kestrel/tools/compiler/diagnostics.test.ks` covering Severity variants, location helpers, and reporter accumulation.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test stdlib/kestrel/tools/compiler/diagnostics.test.ks`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/diagnostics.test.ks` | Verify each severity variant can be encoded in a `Diagnostic` value and inspected by helper predicates. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/diagnostics.test.ks` | Verify `locationFromSpan` copies file/line/column and computes end coordinates when source text is provided. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/diagnostics.test.ks` | Verify reporter accumulation order and `hasErrors` behaviour for warning-only vs error-containing lists. |

## Documentation and specs to update

- [x] `docs/specs/10-compile-diagnostics.md` — add note that `kestrel:tools/compiler/diagnostics` mirrors the compiler Diagnostic schema and error-code strings for self-hosting bootstrap parity.
- [x] `docs/guide.md` — add short note in compiler-development section listing `stdlib/kestrel/tools/compiler/diagnostics.ks` and `reporter.ks` as the Kestrel-side diagnostics implementation.

## Spec References

- `docs/specs/10-compile-diagnostics.md` — diagnostic codes and output format
- `compiler/src/diagnostics/types.ts`
- `compiler/src/diagnostics/reporter.ts`

## Risks / Notes

- Kestrel does not have `symbol` keys, so the TypeScript `CODES` namespace object must be
  represented as exported `val` constants or a record of strings.
- Source-content-aware endLine/endColumn calculation (from `reporter.ts`) requires string
  indexing; use `kestrel:data/string` utilities.
- The `DiagnosticReporter` in TypeScript uses mutable state; in Kestrel use a `var` inside an
  opaque wrapper or pass a `List` as a `var`.

## Build notes

- 2026-04-11: Started implementation.
- 2026-04-11: Kestrel constructor matching in patterns cannot use module-qualified names (for example `Diag.Error`), while expression values can (`Diag.Error`). `hasErrors` uses direct equality (`s == Diag.Error`) to avoid parser limitations in namespaced pattern matches.
- 2026-04-11: Implemented a minimal human reporter first (header + caret + optional hint/note). Source-line extraction from full source text is deferred to a later story once the broader self-hosted compiler pipeline is in place.
