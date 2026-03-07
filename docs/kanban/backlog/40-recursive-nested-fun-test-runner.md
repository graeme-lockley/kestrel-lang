# Fix Recursive Nested Function in Test Runner Context

## Priority: 40 (High)

## Summary

A nested `fun` with a full type signature that calls itself recursively works correctly in normal execution (inline blocks, if branches, returned closures, top-level fun bodies). However, when the same code runs inside the test runner's closure context, the VM hits a bus error. This is documented as a known limitation in spec 01 &sect;3.8.

## Current State

- The bus error occurs specifically when a recursive nested `fun` is invoked within the test runner's closure-based harness.
- The test runner (`scripts/run_tests.ks`) dynamically generates code that calls each test file's `run` function, which creates closure contexts.
- Root cause is not yet identified -- likely related to how closure environments interact with recursive self-references in the CLOSURE/CALL_INDIRECT path.

## Acceptance Criteria

- [ ] Investigate and identify root cause (likely in `exec.zig` CALL_INDIRECT or MAKE_CLOSURE when dealing with recursive self-reference in env).
- [ ] Fix the VM and/or compiler to support recursive nested `fun` in all contexts, including closures.
- [ ] Add a Kestrel unit test (`tests/unit/functions.test.ks` or new file) that exercises recursive nested `fun` -- this test must pass via `kestrel test`, not just `kestrel run`.
- [ ] Remove the "Known limitations" note from spec 01 &sect;3.8 once fixed.

## Spec References

- 01-language &sect;3.8 (Closures and Capture -- known limitation)
- 04-bytecode-isa &sect;5.1 (Closure conversion for nested functions)
