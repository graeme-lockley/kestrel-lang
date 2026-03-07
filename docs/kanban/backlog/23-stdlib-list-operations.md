# Stdlib List Operations Completeness

## Priority: 23 (Medium)

## Summary

The `kestrel:list` module currently provides only `length`, `isEmpty`, and `drop`. The spec and common usage patterns require many more list operations: `map`, `filter`, `foldl`, `foldr`, `reverse`, `concat`, `take`, `head`, `tail`, `zip`, etc. These are essential for idiomatic functional programming in Kestrel.

## Current State

- `stdlib/kestrel/list.ks` exports: `length(l)`, `isEmpty(l)`, `drop(l, n)`.
- `stdlib/kestrel/list.test.ks` tests these three functions.
- List is an ADT with Nil/Cons constructors; `[]`, `::`, and list literal syntax all work.
- The spec (02) says "Constructors and functions for Option, Result, and List (e.g., map, flatMap, getOrElse) are defined in the library; their modules and signatures are implementation-defined beyond the type names above."

## Acceptance Criteria

- [ ] `map(l: List<T>, f: (T) -> U): List<U>` -- apply f to each element.
- [ ] `filter(l: List<T>, f: (T) -> Bool): List<T>` -- keep elements where f returns True.
- [ ] `foldl(l: List<T>, init: U, f: (U, T) -> U): U` -- left fold.
- [ ] `foldr(l: List<T>, init: U, f: (T, U) -> U): U` -- right fold.
- [ ] `reverse(l: List<T>): List<T>` -- reverse the list.
- [ ] `concat(a: List<T>, b: List<T>): List<T>` -- concatenate two lists.
- [ ] `take(l: List<T>, n: Int): List<T>` -- first n elements.
- [ ] `head(l: List<T>): Option<T>` -- first element or None.
- [ ] `tail(l: List<T>): Option<List<T>>` -- all but first, or None.
- [ ] `any(l: List<T>, f: (T) -> Bool): Bool` -- True if any element satisfies f.
- [ ] `all(l: List<T>, f: (T) -> Bool): Bool` -- True if all elements satisfy f.
- [ ] Kestrel tests for each new function.

## Spec References

- 02-stdlib (List<T>: constructors and functions are implementation-defined)
