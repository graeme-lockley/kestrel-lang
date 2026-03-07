# VM Integer Overflow and Division-by-Zero Exceptions

## Priority: 06 (High)

## Summary

The spec requires that integer overflow throws an exception (spec 01 &sect;2.6, 05 &sect;1) and that division/modulo by zero throws (spec 04 &sect;1.2). Currently the VM silently wraps on overflow and returns 0 for division by zero. This violates the spec and can produce silently incorrect results.

## Current State

- **Integer overflow**: 61-bit arithmetic wraps silently. No overflow detection.
- **Division by zero**: `DIV` and `MOD` return 0 instead of throwing. The `@divTrunc` call may actually trap on some platforms (undefined behavior in Zig for division by zero), but the current code doesn't handle it.
- **POW**: No overflow detection for exponentiation.

## Acceptance Criteria

- [ ] ADD, SUB, MUL: Detect 61-bit signed overflow before storing the result. On overflow, throw a runtime exception (e.g., an ArithmeticOverflow ADT or a VM trap that produces a meaningful error message).
- [ ] DIV, MOD: Check for zero divisor before dividing. On zero, throw a DivideByZero exception.
- [ ] POW: Detect overflow in exponentiation result.
- [ ] Define how runtime exceptions are represented (built-in ADT constructors for ArithmeticOverflow and DivideByZero, or a string-based error message).
- [ ] Kestrel test: integer overflow detected and catchable via try/catch.
- [ ] Kestrel test: division by zero caught.
- [ ] Kestrel test: modulo by zero caught.

## Spec References

- 01-language &sect;2.6 (61-bit signed integer; overflow throws)
- 04-bytecode-isa &sect;1.2 (DIV/MOD divide-by-zero throws)
- 05-runtime-model &sect;1 (INT overflow must throw)
