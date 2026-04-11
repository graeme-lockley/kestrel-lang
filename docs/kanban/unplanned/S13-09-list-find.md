# `List.find`, `List.findIndex`, `List.findMap`, `List.last`

## Sequence: S13-09
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add four commonly-needed list search/access functions to `kestrel:data/list`. These eliminate verbose `filter` + `head` and `length` + `drop` patterns that would appear constantly in compiler code.

## Current State

`stdlib/kestrel/data/list.ks` has `filter`, `filterMap`, `head`, `length`, `drop` — but no direct `find`, `findIndex`, `findMap`, or `last`. To find an element currently requires `filter(xs, pred) |> head`.

## Goals

1. Export `find(pred: (A) -> Bool, xs: List<A>): Option<A>` — first element matching predicate, or `None`.
2. Export `findIndex(pred: (A) -> Bool, xs: List<A>): Option<Int>` — index of first matching element, or `None`.
3. Export `findMap(f: (A) -> Option<B>, xs: List<A>): Option<B>` — first `Some(b)` returned by `f`, or `None`.
4. Export `last(xs: List<A>): Option<A>` — last element of list, or `None` for empty.

## Acceptance Criteria

- `find(fun(x) = x > 2, [1, 2, 3, 4])` returns `Some(3)`.
- `find(fun(x) = x > 10, [1, 2, 3])` returns `None`.
- `findIndex(fun(x) = x == 3, [1, 2, 3, 4])` returns `Some(2)`.
- `findIndex(fun(x) = x == 99, [1, 2])` returns `None`.
- `findMap(fun(x) = if (x > 2) Some(x * 10) else None, [1, 2, 3])` returns `Some(30)`.
- `last([1, 2, 3])` returns `Some(3)`.
- `last([])` returns `None`.

## Spec References

- `docs/specs/02-stdlib.md` (data/list section)

## Risks / Notes

- Pure Kestrel implementation; no JVM runtime changes needed.
- `findMap` can short-circuit (return as soon as `f` returns `Some`).
- Independent of all other E13 stories.
