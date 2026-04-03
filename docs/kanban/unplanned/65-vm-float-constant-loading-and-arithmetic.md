# JVM: Float constant loading and arithmetic

## Sequence: 65
## Tier: Verification / residual runtime (may already be done)
## Former ID: 28

## Summary

Historically, the constant pool supported Float in the compiler while the VM loader mapped float constants incorrectly (e.g. to `Unit`). This story tracks **verifying** the current JVM backend behaviour and closing any remaining gaps.

## Current State (verify in tree)

- Kestrel unit tests such as `tests/unit/float.test.ks` exercise float literals and arithmetic; if they pass on the JVM target, loader and arithmetic paths are largely correct.
- Confirm in the JVM runtime (`runtime/jvm/`) that float constants are handled correctly per spec 05 (Float on heap, PTR on stack).
- Confirm ADD/SUB/MUL/DIV (and comparisons) handle Float operands per language semantics on the JVM.

## Acceptance Criteria

- [ ] Audit JVM runtime: Float constants become boxed float values (not Unit); document finding in story Tasks when picked up.
- [ ] If any gap remains: fix JVM runtime float handling; add appropriate tests.
- [ ] Ensure `cd compiler && npm test` and `./scripts/kestrel test` include float coverage on the JVM target.
- [ ] If fully implemented: mark story complete and optionally add a one-line "completion note" in the file body; no further code required.

## Spec References

- 03-bytecode-format (constant pool: Float)
- 05-runtime-model §1–2 (Float boxed on heap; Int inline)
- 04-bytecode-isa (arithmetic and comparison on Float where specified)
