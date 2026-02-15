# VM: Float constant loading and arithmetic

## Description

The constant pool supports Float (tag 1) in the compiler, but the VM loader maps tag 1 to `Value.unit()` instead of creating a boxed FLOAT heap object. Float literals and Float arithmetic do not work.

Per spec 05: Float is always boxed (PTR to FLOAT heap object); Int is inline.

## Acceptance Criteria

- [ ] VM loader: tag 1 (Float) → allocate FLOAT heap object, push PTR
- [ ] VM: arithmetic ops (ADD, SUB, etc.) handle Float operands (or reject non-Int; spec may restrict to Int for v1)
- [ ] Add FLOAT_KIND to heap object kinds in gc.zig if needed
- [ ] E2E scenario with float literal and/or float arithmetic
