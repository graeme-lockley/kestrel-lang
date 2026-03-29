# VM Integer Overflow and Division-by-Zero Exceptions


## Sequence: 25
## Former ID: 30
## Priority: 30 (High)

## Summary

The spec requires that integer overflow throws an exception (spec 01 &sect;2.6, 05 &sect;1) and that division/modulo by zero throws (spec 04 &sect;1.2). Currently the VM silently wraps on overflow and returns 0 for division by zero. This violates the spec and can produce silently incorrect results.

## Current State

- **Integer overflow**: 61-bit arithmetic wraps silently. No overflow detection.
- **Division by zero**: `DIV` and `MOD` return 0 instead of throwing. The `@divTrunc` call may actually trap on some platforms (undefined behavior in Zig for division by zero), but the current code doesn't handle it.
- **POW**: No overflow detection for exponentiation.

## Acceptance Criteria

- [x] ADD, SUB, MUL: Detect 61-bit signed overflow before storing the result. On overflow, throw a runtime exception (e.g., an ArithmeticOverflow ADT or a VM trap that produces a meaningful error message).
- [x] DIV, MOD: Check for zero divisor before dividing. On zero, throw a DivideByZero exception.
- [x] POW: Detect overflow in exponentiation result.
- [x] Define how runtime exceptions are represented (built-in ADT constructors for ArithmeticOverflow and DivideByZero, or a string-based error message).
- [x] Kestrel test: integer overflow detected and catchable via try/catch.
- [x] Kestrel test: division by zero caught.
- [x] Kestrel test: modulo by zero caught.

## Tasks

- [x] ADD, SUB, MUL: detect 61-bit overflow; throw ArithmeticOverflow via VM
- [x] DIV, MOD: check zero divisor; throw DivideByZero via VM
- [x] POW: detect integer exponentiation overflow; throw ArithmeticOverflow
- [x] Represent runtime exceptions as ADT values (look up by name in current module)
- [x] Kestrel unit test: integer overflow caught in try/catch
- [x] Kestrel unit test: division by zero caught
- [x] Kestrel unit test: modulo by zero caught

## Spec References

- 01-language &sect;2.6 (61-bit signed integer; overflow throws)
- 04-bytecode-isa &sect;1.2 (DIV/MOD divide-by-zero throws)
- 05-runtime-model &sect;1 (INT overflow must throw)
