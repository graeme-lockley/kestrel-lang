# VM: Float constant loading and arithmetic

## Sequence: 62
## Tier: Verification / residual runtime (may already be done)
## Former ID: 28

## Summary

Historically, the constant pool supported Float in the compiler while the VM loader mapped float constants incorrectly (e.g. to `Unit`), breaking float literals and float arithmetic on the VM. This story tracks **verifying** the current VM and loader behaviour and closing any remaining gaps.

## Current State (verify in tree)

- Kestrel unit tests such as `tests/unit/float.test.ks` exercise float literals and arithmetic; if they pass on the default VM target, loader and arithmetic paths are largely correct.
- Confirm in `vm/src/load.zig` (or equivalent) that constant pool tag for Float allocates or references a boxed float per spec 05 (Float on heap, PTR on stack).
- Confirm ADD/SUB/MUL/DIV (and comparisons) handle Float operands per language semantics.

## Acceptance Criteria

- [ ] Audit VM loader: Float constants become boxed float values (not Unit); document finding in story Tasks when picked up.
- [ ] If any gap remains: fix loader and/or opcode handlers; add `FLOAT_KIND` or equivalent tracing in GC if missing.
- [ ] Ensure `zig build test` and `./scripts/kestrel test` include float coverage on VM.
- [ ] If fully implemented: mark story complete and optionally add a one-line "completion note" in the file body; no further code required.

## Spec References

- 03-bytecode-format (constant pool: Float)
- 05-runtime-model §1–2 (Float boxed on heap; Int inline)
- 04-bytecode-isa (arithmetic and comparison on Float where specified)
