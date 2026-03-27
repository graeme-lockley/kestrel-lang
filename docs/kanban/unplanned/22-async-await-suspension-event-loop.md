# Async/Await: Real Suspension and Event Loop

## Sequence: 22
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 150

## Summary

The current AWAIT implementation only handles **completed** tasks (synchronous returns). If a task is pending, the VM returns unit instead of suspending the frame. For a real async system (file I/O, HTTP, timers), the VM needs frame suspension, an event loop, and task scheduling.

## Current State

- AWAIT opcode: checks if TASK is completed; if so, pushes result. If pending, pushes unit.
- `readFileAsync` primitive: may read file synchronously and return a completed TASK; there is no actual async I/O in the typical sense.
- No event loop, no I/O multiplexing, no frame suspension/resumption.
- The compiler correctly emits AWAIT for `await expr` in async functions.

## Scope Note

This is a large feature that is deferred until the language and VM test story (sequence **05**) and core correctness work are in good shape. Full async is needed for the HTTP server (sequence **19**) and concurrent I/O scenarios.

## Dependencies

- Sequences **04**–**06** (runtime safety and tests) reduce risk before large VM changes.

## Acceptance Criteria

- [ ] Frame suspension: when AWAIT sees a pending TASK, save the current frame (PC, locals, stack segment) and return to the scheduler.
- [ ] Event loop: a main loop that checks for completed I/O, resumes suspended frames, and runs ready tasks.
- [ ] `readText` or async read returns a genuinely async TASK (I/O completes in the background) where the spec requires it.
- [ ] Multiple concurrent tasks can be in flight.
- [ ] E2E test: two async file reads happening concurrently.

## Spec References

- 01-language §5 (Async and Task model)
- 04-bytecode-isa §1.9 (AWAIT: if suspended, suspend frame)
- 05-runtime-model §6 (TASK suspended vs completed; event-loop-driven I/O)
