# JVM: Float constant loading and arithmetic

## Sequence: S06-04
## Tier: Verification / residual runtime (may already be done)
## Former ID: 28

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)
- Companion stories: S06-03, S06-05

## Summary

Historically, the constant pool supported Float in the compiler while the VM loader mapped float constants incorrectly (e.g. to `Unit`). This story tracks **verifying** the current JVM backend behaviour and closing any remaining gaps.

## Current State (verify in tree)

- Kestrel unit tests such as `tests/unit/float.test.ks` exercise float literals and arithmetic; if they pass on the JVM target, loader and arithmetic paths are largely correct.
- Confirm in the JVM runtime (`runtime/jvm/`) that float constants are handled correctly per spec 05 (Float on heap, PTR on stack).
- Confirm ADD/SUB/MUL/DIV (and comparisons) handle Float operands per language semantics on the JVM.

## Acceptance Criteria

- [x] Audit JVM runtime: Float constants become boxed float values (not Unit); document finding in story Tasks when picked up.
- [x] If any gap remains: fix JVM runtime float handling; add appropriate tests.
- [x] Ensure `cd compiler && npm test` and `./scripts/kestrel test` include float coverage on the JVM target.
- [x] If fully implemented: mark story complete and optionally add a one-line "completion note" in the file body; no further code required.

## Spec References

- 03-bytecode-format (constant pool: Float)
- 05-runtime-model §1–2 (Float boxed on heap; Int inline)
- 04-bytecode-isa (arithmetic and comparison on Float where specified)

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `KMath.java` — `addFloat`, `subFloat`, `mulFloat`, `divFloat`, `powFloat`, `<`/`<=`/`>`/`>=` all implemented as `Double` ops; no change needed |
| JVM runtime | `KRuntime.java` — discriminant 5 is `Float (Double)`, `intToFloat`/`floatToInt`/`floatFloor`/`floatCeil` all implemented |
| Tests | `tests/unit/float.test.ks` — literals, arithmetic, comparison groups |
| Tests | `tests/conformance/runtime/valid/float_ops.ks` — literals, arithmetic, comparison |

## Tasks

- [x] Confirm `KMath.java` handles `addFloat`, `subFloat`, `mulFloat`, `divFloat`, `powFloat`, and comparison ops
- [x] Confirm `KRuntime.java` uses `Double` for Float constants (discriminant 5)
- [x] Confirm `tests/unit/float.test.ks` covers literals, arithmetic, and comparison
- [x] Confirm `tests/conformance/runtime/valid/float_ops.ks` exists and passes

## Tests to add

None — coverage already exists.

## Documentation and specs to update

None — implementation is correct per spec.

## Build notes

- 2026-04-05: Verified. `KMath.java` has complete float arithmetic and comparison helpers (all operating on `Double`). `KRuntime.java` uses discriminant 5 for `Float (Double)`. Tests pass in both `tests/unit/float.test.ks` and `tests/conformance/runtime/valid/float_ops.ks`. No code changes required; closing as verified.
