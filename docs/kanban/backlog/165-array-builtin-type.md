# Array<T> Built-in Type

## Priority: 165 (Low -- deferred)

## Summary

`Array<T>` is specified as a runtime built-in (spec 01 &sect;3.6, 05 &sect;2) -- a mutable, contiguous sequence of values. Currently, no ARRAY heap kind exists. Lists (immutable linked list via ADT Cons/Nil) are the only collection type. Array would provide O(1) indexed access, which List cannot.

## Current State

- Type system: `Array<T>` is parsed as an `AppType` with name "Array".
- VM: No ARRAY heap object kind.
- No array creation, indexing, or mutation instructions.
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

- 01-language &sect;3.6 (Array<T> built-in generic)
- 05-runtime-model &sect;2 (ARRAY heap kind)
- 06-typesystem &sect;1 (Array<T> type)
