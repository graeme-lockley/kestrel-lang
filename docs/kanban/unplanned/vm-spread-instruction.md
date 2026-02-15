# VM: Implement SPREAD instruction

## Description

The compiler emits the **SPREAD** opcode (0x19) for record spread expressions `{ ...r, x = v }`, but the VM does not handle it. When SPREAD is encountered, execution hits `else => return` and stops.

## Acceptance Criteria

- [ ] Add SPREAD (0x19) handling in `vm/src/exec.zig`
- [ ] Pop record and additional values; produce new record with extended shape per spec 04 §1.8
- [ ] Add E2E scenario that uses record spread `{ ...r, x = v }` and assert output
