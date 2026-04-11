# `Dict` with structural-equality keys (`StructDict`)

## Sequence: S13-12
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add a `kestrel:data/structdict` module providing `StructDict<K,V>` — a dictionary where keys are compared by structural (value) equality rather than reference identity. The current `Dict<K,V>` uses Java's `HashMap` which relies on `.equals()` and `.hashCode()`. Kestrel ADT and record values use reference-identity `.equals()`, so they cannot be used as `Dict` keys without structural issues. A `StructDict` backed by a serialized-key strategy fixes this.

## Current State

`data/dict.ks` uses `HashMap<Object,Object>` via KRuntime. ADT and record keys compare by reference identity. String and Int keys work correctly because Java's `String.equals` and `Long.equals` are structural. For the compiler, most environments use `String` keys, but a type-environment keyed by compound types would need structural equality.

## Goals

1. Add `kestrel:data/structdict` module with `StructDict<K,V>` opaque type.
2. The backing can use `LinkedHashMap<String, V>` where the key is serialized via `formatOne` — a deterministic structural-to-string mapping.
3. Export: `empty`, `singleton`, `insert`, `remove`, `get`, `member`, `size`, `keys`, `values`, `toList`, `fromList`, `map`, `filter`, `foldl`, `foldr`, `union`, `intersect`, `diff`.
4. Key serialization uses `KRuntime.formatOne` (or a new `KRuntime.structKey(Object)` variant that produces a canonical string from any value).

## Acceptance Criteria

- Two ADT values `Some(1)` and `Some(1)` (created separately) can both be used as keys and resolve to the same entry.
- Two records `{x=1}` and `{x=1}` created separately map to the same key.
- `String` and `Int` keys behave identically to `Dict`.
- `insert`, `get`, `remove`, `member` all work correctly with structural ADT keys.

## Spec References

- `docs/specs/02-stdlib.md` (data/structdict section — new)

## Risks / Notes

- Key serialization via `formatOne` is only faithful if `formatOne` produces unique strings for structurally distinct values and identical strings for structurally equal values. This is true for ADTs, records, primitives, and lists. It is NOT true for mutable `Array<T>` (reference-based). Document this limitation.
- This story is "polish" — not needed for the compiler rewrite as the compiler uses only string-keyed `Dict` — but valuable for preventing subtle bugs in future compiler code.
- Independent of all other E13 stories.
