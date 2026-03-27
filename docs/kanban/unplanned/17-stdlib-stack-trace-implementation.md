# Stdlib kestrel:stack trace() Implementation

## Sequence: 17
## Tier: 4 — Stdlib and test harness
## Former ID: 125

## Summary

The `kestrel:stack` module provides `format()` and `print()` but `trace()` is deferred. Spec 02 requires `trace(T) -> StackTrace<T>` which captures a stack trace for a thrown value. This requires a VM primitive (`__capture_trace`) and a `StackTrace<T>` type definition.

## Current State

- `stdlib/kestrel/stack.ks` exports `format()` (via `__format_one`) and `print()` (via `__print_one`).
- `trace()` is not implemented -- no VM primitive, no StackTrace type.
- The bytecode debug section (see completed work in `docs/kanban/done/`) provides code-offset-to-line mapping; stack traces should use it where available.

## Acceptance Criteria

- [ ] Define `StackTrace<T>` type (ADT or record) in the stdlib -- e.g., `{ value: T, frames: List<{ file: String, line: Int, function: String }> }`.
- [ ] Implement `__capture_trace` VM primitive that captures the current call stack (using debug section data if available).
- [ ] `trace(value)` in `stack.ks` calls the primitive and returns a StackTrace.
- [ ] `format(trace)` or a `formatTrace` function produces a human-readable stack trace string.
- [ ] E2E test: throw an exception, catch it, call `trace()`, verify it contains frame information.

## Spec References

- 02-stdlib (kestrel:stack: trace(T) -> StackTrace<T>)
- 05-runtime-model §5 (Stack traces: runtime may capture backtrace at throw time)
- 03-bytecode-format §8 (Debug section maps code offsets to file/line)
