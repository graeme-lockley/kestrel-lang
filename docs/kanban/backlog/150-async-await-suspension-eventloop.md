# Async/Await: Real Suspension and Event Loop

## Priority: 150 (Low -- deferred)

## Summary

The current AWAIT implementation only handles **completed** tasks (synchronous returns). If a task is pending, the VM returns unit instead of suspending the frame. For a real async system (file I/O, HTTP, timers), the VM needs frame suspension, an event loop, and task scheduling.

## Current State

- AWAIT opcode: checks if TASK is completed; if so, pushes result. If pending, pushes unit.
- `readFileAsync` primitive: reads file synchronously, creates a completed TASK, returns it. There is no actual async I/O.
- No event loop, no I/O multiplexing, no frame suspension/resumption.
- The compiler correctly emits AWAIT for `await expr` in async functions.

## Scope Note

This is a large feature that is deferred to later. The current synchronous-only approach works for scripts and basic programs. Full async is needed for the HTTP server and concurrent I/O scenarios.

## Acceptance Criteria

- [ ] Frame suspension: when AWAIT sees a pending TASK, save the current frame (PC, locals, stack segment) and return to the scheduler.
- [ ] Event loop: a main loop that checks for completed I/O, resumes suspended frames, and runs ready tasks.
- [ ] `readText` returns a genuinely async TASK (I/O completes in the background).
- [ ] Multiple concurrent tasks can be in flight.
- [ ] E2E test: two async file reads happening concurrently.

## Spec References

- 01-language &sect;5 (Async and Task model)
- 04-bytecode-isa &sect;1.9 (AWAIT: if suspended, suspend frame)
- 05-runtime-model &sect;6 (TASK suspended vs completed; event-loop-driven I/O)
