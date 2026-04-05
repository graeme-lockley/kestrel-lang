# Int 64-bit JVM Native Representation

## Sequence: S06-03
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)
- Companion stories: 67, 71

## Summary

Migrate Int semantics from VM-era 61-bit limits to JVM-native signed 64-bit behavior, making Long the authoritative runtime representation for Int in Kestrel's JVM-only implementation.

## Current State

- Current language/runtime specs still describe Int as 61-bit because of historical tagged-value VM layout assumptions.
- JVM runtime arithmetic helpers still enforce 61-bit range checks for overflow behavior.
- Overflow unit tests currently target 61-bit boundaries.
- JVM-only pivot work is already underway, so VM-specific integer representation constraints are no longer a valid source-of-truth for runtime behavior.

## Relationship to other stories

- Depends on JVM-only pivot direction established in stories 55-58.
- Should be sequenced after tooling/runtime cleanup that removes VM dependency assumptions from everyday workflows.
- Supersedes VM-era 61-bit rationale captured by older overflow stories in done.
- Aligns with specs-alignment work so Int width semantics become consistently JVM-native across docs and implementation.

## Goals

- Define Int runtime semantics as signed 64-bit on the JVM backend.
- Remove remaining 61-bit assumptions from runtime arithmetic checks and related diagnostics.
- Preserve catchable overflow and divide-by-zero behavior with 64-bit boundaries.
- Update tests and fixtures so they validate 64-bit Int boundaries and failure modes.
- Ensure docs/spec text no longer references VM-tagged 61-bit Int constraints as normative behavior.

## Acceptance Criteria

- [x] JVM arithmetic paths enforce 64-bit overflow semantics (Long.MIN_VALUE to Long.MAX_VALUE), not 61-bit bounds.
- [x] Int overflow remains catchable as ArithmeticOverflow under updated 64-bit behavior.
- [x] Divide-by-zero and modulo-by-zero behavior remains unchanged and catchable as DivideByZero.
- [x] Compiler/runtime diagnostics no longer claim Int is 61-bit.
- [x] Existing overflow/div-zero tests are updated for 64-bit boundaries and pass in JVM-only test runs.
- [x] Conformance/runtime tests that reference Int range assumptions are updated and pass.
- [x] No acceptance path for this story depends on a VM implementation.

## Spec References

- docs/specs/01-language.md
- docs/specs/02-stdlib.md
- docs/specs/08-tests.md

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `KMath.java` — remove `MAX_61`/`MIN_61`/`check61()`; replace with `Math.addExact`/`subtractExact`/`multiplyExact`; update `pow()` to use multiply overflow checks; change error message from `"61-bit integer overflow"` to `"integer overflow"` |
| Tests | `tests/unit/overflow_divzero.test.ks` — update `halfMax` from `2^59` to `2^62` and comment |
| Docs | `docs/specs/01-language.md` §2.6 — change "61-bit signed integer" to "signed 64-bit integer (Long.MIN_VALUE to Long.MAX_VALUE)" |
| Docs | `docs/specs/02-stdlib.md` — update `ArithmeticOverflow` description from "VM-defined width" to "64-bit width" |
| Docs | `docs/specs/08-tests.md` — change "61-bit Int overflow" to "64-bit Int overflow" |

## Tasks

- [x] Update `KMath.java`: remove `MAX_61`, `MIN_61`, `check61()`; use `Math.addExact`/`subtractExact`/`multiplyExact`; update `pow()` overflow guards; change error messages
- [x] Update `tests/unit/overflow_divzero.test.ks`: set `halfMax = 4611686018427387904` (2^62), update comment
- [x] Update `docs/specs/01-language.md` §2.6: "61-bit signed integer" → "signed 64-bit integer (Long.MIN_VALUE to Long.MAX_VALUE)"
- [x] Update `docs/specs/02-stdlib.md`: `ArithmeticOverflow` description from "VM-defined width" to "64-bit width"
- [x] Update `docs/specs/08-tests.md`: "61-bit Int overflow" → "64-bit Int overflow"
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `tests/unit/overflow_divzero.test.ks` | Update boundary values to 64-bit; same ADD/SUB/MUL overflow + DivideByZero/ModByZero tests |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — §2.6 Int literal: change "61-bit signed integer" to "signed 64-bit integer (Long.MIN_VALUE to Long.MAX_VALUE)"
- [x] `docs/specs/02-stdlib.md` — `ArithmeticOverflow` row: remove "VM-defined width"
- [x] `docs/specs/08-tests.md` — overflow_divzero description: "61-bit" → "64-bit"

## Build notes

- 2026-04-05: Replaced `MAX_61`/`MIN_61`/`check61()` in `KMath.java` with `Math.addExact`/`subtractExact`/`multiplyExact` (standard Java signed-64-bit overflow detection). `pow()` helper wraps its multiplications the same way. `normalizeCaught()` already uses any non-"division by zero" `ArithmeticException` as `ArithmeticOverflow`, so no runtime dispatch change needed. Updated `overflow_divzero.test.ks` boundary from 2^59 to 2^62 so `halfMax + halfMax` = 2^63 triggers the 64-bit overflow. All 1070 Kestrel tests pass; 3 compiler test failures are pre-existing E04 url-import tests, unrelated to this story.
