# Stdlib kestrel:stack trace() Implementation

## Priority: 25 (Medium)

## Summary

The `kestrel:stack` module provides `format()` and `print()` but `trace()` is deferred. Spec 02 requires `trace(T) -> StackTrace<T>` which captures a stack trace for a thrown value. This requires a VM primitive (`__capture_trace`) and a `StackTrace<T>` type definition.

## Current State

- `stdlib/kestrel/stack.ks` exports `format()` (via `__format_one`) and `print()` (via `__print_one`).
- `trace()` is not implemented -- no VM primitive, no StackTrace type.
- The debug section (story 06) is a prerequisite: without code-offset-to-line mapping, stack traces would only show raw offsets.

## Dependencies

- Story 06 (Debug Section) should be completed first to provide meaningful line numbers.

## Acceptance Criteria

- [ ] Define `StackTrace<T>` type (ADT or record) in the stdlib -- e.g., `{ value: T, frames: List<{ file: String, line: Int, function: String }> }`.
- [ ] Implement `__capture_trace` VM primitive that captures the current call stack (using debug section data if available).
- [ ] `trace(value)` in `stack.ks` calls the primitive and returns a StackTrace.
- [ ] `format(trace)` or a `formatTrace` function produces a human-readable stack trace string.
- [ ] E2E test: throw an exception, catch it, call `trace()`, verify it contains frame information.

## Spec References

- 02-stdlib (kestrel:stack: trace(T) -> StackTrace<T>)
- 05-runtime-model &sect;5 (Stack traces: runtime may capture backtrace at throw time)
- 03-bytecode-format &sect;8 (Debug section maps code offsets to file/line)
