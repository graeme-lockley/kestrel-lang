# Stdlib List Operations Completeness

## Priority: 115 (Medium)

## Summary

The `kestrel:list` module currently provides only `length`, `isEmpty`, and `drop`. The spec and common usage patterns require many more list operations: `map`, `filter`, `foldl`, `foldr`, `reverse`, `concat`, `take`, `head`, `tail`, `zip`, etc. These are essential for idiomatic functional programming in Kestrel.

## Current State

- `stdlib/kestrel/list.ks` exports: `length(l)`, `isEmpty(l)`, `drop(l, n)`.
- `stdlib/kestrel/list.test.ks` tests these three functions.
- List is an ADT with Nil/Cons constructors; `[]`, `::`, and list literal syntax all work.
- The spec (02) says "Constructors and functions for Option, Result, and List (e.g., map, flatMap, getOrElse) are defined in the library; their modules and signatures are implementation-defined beyond the type names above."

## Acceptance Criteria

- [x] `map(l: List<T>, f: (T) -> U): List<U>` -- apply f to each element.
- [x] `filter(l: List<T>, f: (T) -> Bool): List<T>` -- keep elements where f returns True.
- [x] `foldl(l: List<T>, init: U, f: (U, T) -> U): U` -- left fold.
- [x] `foldr(l: List<T>, init: U, f: (T, U) -> U): U` -- right fold.
- [x] `reverse(l: List<T>): List<T>` -- reverse the list.
- [x] `concat(a: List<T>, b: List<T>): List<T>` -- concatenate two lists.
- [x] `take(l: List<T>, n: Int): List<T>` -- first n elements.
- [x] `head(l: List<T>): Option<T>` -- first element or None.
- [x] `tail(l: List<T>): Option<List<T>>` -- all but first, or None.
- [x] `any(l: List<T>, f: (T) -> Bool): Bool` -- True if any element satisfies f.
- [x] `all(l: List<T>, f: (T) -> Bool): Bool` -- True if all elements satisfy f.
- [x] Kestrel tests for each new function.

## Completion Note

All spec functions plus extras (singleton, sum, product, maximum, minimum, partition, unzip, sort, etc.) are implemented and tested. Moved to done.

## Spec References

- 02-stdlib (List<T>: constructors and functions are implementation-defined)
