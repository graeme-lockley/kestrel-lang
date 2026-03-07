# VM GC: Trace Module Globals as Roots

## Priority: 35 (High)

## Summary

The garbage collector does not trace module globals as roots. If a module stores a heap-allocated value (string, record, ADT, closure) in a global slot and the GC runs when that value is not also referenced from the stack or locals, the object could be freed prematurely, causing a use-after-free.

## Current State

- `gc.zig` `markRoots()` traces only the operand stack and all saved local slots across call frames.
- Module globals are stored as `[]Value` slices allocated per module in `exec.zig`, but these are not passed to the GC as roots.
- In practice, globals are often also on the stack or in locals, so this hasn't caused observable crashes yet. But it's a latent correctness bug.

## Acceptance Criteria

- [ ] Pass all module globals slices to `markRoots()` alongside the stack and locals.
- [ ] Ensure the GC can handle an arbitrary number of modules (not just the entry module).
- [ ] Add a stress test: store a large heap object in a global, trigger GC, verify the global still points to valid data.

## Spec References

- 05-runtime-model &sect;4 (Roots: operand stack + locals of all frames + globals)
