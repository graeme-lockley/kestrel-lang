# Generic `List.sortBy` and `List.sortWith`

## Sequence: S13-08
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add `sortBy` (sort by a key function) and `sortWith` (sort by a comparator) to `kestrel:data/list`. The compiler needs to sort lists of type variables, diagnostics by location, import lists alphabetically, and many other ordered structures throughout typechecking and codegen.

## Current State

`stdlib/kestrel/data/list.ks` has `sort(xs: List<Int>)` (insertion sort, Int keys only). No generic sort exists. The implementation is a recursive insertion sort — adequate but not crucial for the compiler use case where lists are typically short.

## Goals

1. Export `sortBy(f: (A) -> Int, xs: List<A>): List<A>` — sort by a key function returning an `Int` (used for comparisons: negative/zero/positive from subtraction, or just an ordinal).
2. Export `sortWith(cmp: (A, A) -> Int, xs: List<A>): List<A>` — sort by a comparator function returning negative/zero/positive.
3. Both use a stable sort algorithm (merge sort or insertion sort for correctness). Insertion sort is fine as the existing `sort` implementation already uses it.

## Acceptance Criteria

- `sortBy(fun(x) = x, [3, 1, 2])` returns `[1, 2, 3]`.
- `sortWith(fun(a, b) = a - b, [3, 1, 2])` returns `[1, 2, 3]`.
- `sortWith(fun(a, b) = b - a, [3, 1, 2])` returns `[3, 2, 1]` (descending).
- `sortBy(fun(s) = String.length(s), ["bb", "a", "ccc"])` returns `["a", "bb", "ccc"]`.
- Both functions work on empty and singleton lists.

## Spec References

- `docs/specs/02-stdlib.md` (data/list section)

## Risks / Notes

- Pure Kestrel implementation; no JVM runtime changes needed.
- `sortBy` can be implemented as `sortWith(fun(a, b) = f(a) - f(b), xs)`.
- Independent of all other E13 stories.
