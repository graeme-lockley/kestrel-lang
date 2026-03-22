# Array<T> Built-in Type

## Sequence: 20
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 165

## Summary

`Array<T>` is specified as a runtime built-in (spec 01 §3.6, 05 §2) -- a mutable, contiguous sequence of values. Currently, no ARRAY heap kind may exist in the VM. Lists (immutable linked list via ADT Cons/Nil) are the primary sequence type. Array would provide O(1) indexed access, which List cannot.

## Current State

- Type system: `Array<T>` is parsed as an `AppType` with name "Array".
- VM: May lack ARRAY heap object kind and dedicated instructions.
- No array creation, indexing, or mutation instructions (unless added elsewhere).
- The spec notes "creation/access impl-defined or stdlib" for ARRAY.

## Acceptance Criteria

- [ ] Add `ARRAY_KIND` to `gc.zig` -- contiguous element storage, length, capacity.
- [ ] Define VM primitives or instructions for array operations:
  - `arrayNew(capacity)` or `arrayFrom(list)` -- create an array.
  - `arrayGet(arr, index)` -- O(1) index access; out-of-bounds throws.
  - `arraySet(arr, index, value)` -- O(1) mutation.
  - `arrayLength(arr)` -- return length.
  - `arrayPush(arr, value)` -- append (may grow).
- [ ] Compiler codegen for `Array<T>` usage.
- [ ] Kestrel test: create array, read, write, iterate.

## Spec References

- 01-language §3.6 (Array<T> built-in generic)
- 05-runtime-model §2 (ARRAY heap kind)
- 06-typesystem §1 (Array<T> type)
