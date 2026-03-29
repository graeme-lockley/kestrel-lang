# Fix Recursive Nested Function in Test Runner Context


## Sequence: 27
## Former ID: 40
## Priority: 40 (High)

## Summary

A nested `fun` with a full type signature that calls itself recursively works correctly in normal execution (inline blocks, if branches, returned closures, top-level fun bodies). However, when the same code runs inside the test runner's closure context, the VM hits a bus error. This is documented as a known limitation in spec 01 &sect;3.8.

## Current State

- Root cause identified: block-level `fun` inside a closure could not capture variables from the parent closure's environment (compiler codegen did not extend free-variable scope with parent captures or forward them when building closure records).
- Fixed in compiler codegen: extended scope for getFreeVars, capture-forwarding when building closure records, isVar propagation from parent captures. Spec 01 §3.8 known limitation removed.

## Acceptance Criteria

- [x] Investigate and identify root cause (likely in `exec.zig` CALL_INDIRECT or MAKE_CLOSURE when dealing with recursive self-reference in env).
- [x] Fix the VM and/or compiler to support recursive nested `fun` in all contexts, including closures.
- [x] Add a Kestrel unit test (`tests/unit/functions.test.ks` or new file) that exercises recursive nested `fun` -- this test must pass via `kestrel test`, not just `kestrel run`.
- [x] Remove the "Known limitations" note from spec 01 &sect;3.8 once fixed.

## Tasks

- [x] Extend getFreeVars scope to include parent captures (single-fun and mutual-recursion paths)
- [x] Add capture-forwarding branch when building closure record values (LOAD_LOCAL 0 + GET_FIELD)
- [x] Propagate isVar from parent captures in singleCaptureMap/captureMap
- [x] Add unit tests for nested fun capturing from outer closure (val, var, recursive, double-nested)
- [x] Remove known limitations note from spec 01 §3.8; move story to done

## Spec References

- 01-language &sect;3.8 (Closures and Capture)
- 04-bytecode-isa &sect;5.1 (Closure conversion for nested functions)
