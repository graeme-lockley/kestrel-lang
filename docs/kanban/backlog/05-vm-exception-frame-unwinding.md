# VM Exception Frame Unwinding Bug

## Priority: 05 (Critical)

## Summary

When THROW executes inside a nested CALL that is deeper than where the TRY handler was set up, the VM does not restore `frame_sp` from the handler's saved `frame_depth`. This means execution continues in the catch block with a corrupted call frame stack. This is a correctness bug that breaks any non-trivial try/catch usage.

## Current State

- `ExceptionHandler` stores `frame_depth` (the frame_sp at the time TRY was pushed), but THROW never reads or uses it.
- THROW restores only `sp` (stack pointer) to `handler.stack_sp` and sets `pc` to `handler.handler_pc`.
- After a THROW from within nested calls, `frame_sp` still points to the deeper frame, `current_module`, `code`, `constants`, `functions`, `shapes`, and `current_locals` are all stale (from the inner function, not the function containing the TRY).
- Simple cases (throw in same function as try) work by coincidence. Throw from a called function will corrupt state.

## Acceptance Criteria

- [ ] When THROW finds a handler, restore `frame_sp` to `handler.frame_depth`.
- [ ] Re-sync `current_module`, `code`, `constants`, `functions`, `shapes`, and `current_locals` from the restored frame.
- [ ] Ensure the exception value is correctly pushed onto the stack after restoring state.
- [ ] Add Kestrel test: throw from a deeply nested function call, catch at the outer level, verify correct value and continued execution.
- [ ] Add Kestrel test: throw from within a closure called inside try, catch correctly.
- [ ] Add Kestrel test: multiple nested try/catch blocks with throws at different depths.

## Spec References

- 04-bytecode-isa &sect;1.9 (TRY, THROW, END_TRY semantics)
- 05-runtime-model &sect;5 (THROW unwinds stack to nearest TRY scope)
