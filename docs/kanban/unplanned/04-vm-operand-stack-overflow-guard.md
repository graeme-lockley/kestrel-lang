# VM Operand Stack Overflow Guard

## Sequence: 04
## Tier: 2 — Harden the runtime
## Former ID: 86

## Summary

The VM operand stack is a fixed-size array of 4096 entries. Push operations (`stack[sp] = ...; sp += 1`) have no bounds check, so deeply recursive programs or malformed bytecode can silently write past the end of the array, causing undefined behavior. Call-frame overflow is already guarded; the operand stack needs the same treatment.

## Current State

- `exec.zig`: stack is `[4096]Value`; every push increments `sp` without checking against the limit.
- Call-frame overflow is checked (lines ~977, ~1005, ~380) and produces a clear error.
- No test exercises deep operand-stack usage.

## Acceptance Criteria

- [ ] Add a bounds check before every `sp += 1` (or a helper that checks), producing a clear "operand stack overflow" runtime error.
- [ ] The error should print a stack trace (reuse the uncaught-exception path).
- [ ] Add a VM test that triggers the guard (e.g., deeply nested expression evaluation).
- [ ] Existing E2E and unit tests still pass.

## Spec References

- 05-runtime-model (stack and frame layout; implementation-defined limits)
