# Int 64-bit JVM Native Representation

## Sequence: 72
## Tier: 8
## Former ID: (none)

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

- [ ] JVM arithmetic paths enforce 64-bit overflow semantics (Long.MIN_VALUE to Long.MAX_VALUE), not 61-bit bounds.
- [ ] Int overflow remains catchable as ArithmeticOverflow under updated 64-bit behavior.
- [ ] Divide-by-zero and modulo-by-zero behavior remains unchanged and catchable as DivideByZero.
- [ ] Compiler/runtime diagnostics no longer claim Int is 61-bit.
- [ ] Existing overflow/div-zero tests are updated for 64-bit boundaries and pass in JVM-only test runs.
- [ ] Conformance/runtime tests that reference Int range assumptions are updated and pass.
- [ ] No acceptance path for this story depends on a VM implementation.

## Spec References

- docs/specs/01-language.md
- docs/specs/03-bytecode-format.md
- docs/specs/05-runtime-model.md
- docs/specs/06-typesystem.md
- docs/specs/08-tests.md
- docs/specs/10-compile-diagnostics.md

## Risks / Notes

- Partial migration risk: implementation may switch to 64-bit while specs/tests still encode 61-bit assumptions.
- Boundary-sensitive tests and literal-range diagnostics are likely to need coordinated updates.
- If any serialized or tooling-facing wording implies 61-bit limits, those references must be reconciled in the same delivery window to avoid user confusion.
- Detailed tasks, impact analysis, and test matrix should be added when this story is promoted to planned.
