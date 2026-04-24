//! Unordered membership sets backed by [`kestrel:data/dict`](/docs/kestrel:data/dict).
//!
//! `Set<E>` is an opaque wrapper around `Dict<E, Unit>`, inheriting O(1) average
//! insert, remove, and membership test. All operations return new sets; the
//! original is never modified.
//!
//! Like `Dict`, functions that build a set from scratch or need to hash/compare
//! elements accept a hash function `(K) -> Int` and an equality function
//! `(K, K) -> Bool`. For `String` or `Int` elements use the convenience
//! constructors (`emptyStringSet`, `fromIntList`, etc.) that hard-code the
//! correct hash/eq pair.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Set from "kestrel:data/set"
//!
//! val s1 = Set.fromIntList([1, 2, 2, 3])
//! val s2 = Set.insert(s1, 4)
//! val has3 = Set.member(s2, 3)                // True
//! val onlyEven = Set.filter(s2, (n: Int) => n % 2 == 0)
//! val both = Set.intersect(s2, Set.fromIntList([2, 4, 9]))
//! val allVals = Set.toList(Set.union(s2, both))
//! ```
//!

import * as List from "kestrel:data/list"
import * as D from "kestrel:data/dict"
import { Dict } from "kestrel:data/dict"

// Parens: parser otherwise treats `= Dict<...>` as starting an ADT body (uppercase ident + `<`).
opaque type Set<E> = (Dict<E, Unit>)

/// An empty set. Requires a hash function and equality predicate for element type `K`.
export fun empty<K>(_hf: (K) -> Int, _eqf: (K, K) -> Bool): Set<K> = D.empty()

/// A set containing exactly one element.
export fun singleton<K>(hf: (K) -> Int, eqf: (K, K) -> Bool, k: K): Set<K> = {
  val u: Unit = ()
  D.singleton(hf, eqf, k, u)
}

/// Return a new set with `k` added (no-op if already present).
export fun insert<K>(s: Set<K>, k: K): Set<K> = {
  val u: Unit = ()
  D.insert(s, k, u)
}

/// Return a new set with `k` removed (no-op if absent).
export fun remove<K>(s: Set<K>, k: K): Set<K> = D.remove(s, k)

/// `True` if `k` is an element of `s`.
export fun member<K>(s: Set<K>, k: K): Bool = D.member(s, k)

/// `True` if the set has no elements.
export fun isEmpty<K>(s: Set<K>): Bool = D.isEmpty(s)

/// Number of elements in the set.
export fun size<K>(s: Set<K>): Int = D.size(s)

/// Elements present in either `s1` or `s2` (union).
export fun union<K>(s1: Set<K>, s2: Set<K>): Set<K> = D.union(s1, s2)

/// Elements present in both `s1` and `s2` (intersection).
export fun intersect<K>(s1: Set<K>, s2: Set<K>): Set<K> = D.intersect(s1, s2)

/// Elements in `s1` that are not in `s2` (difference).
export fun diff<K>(s1: Set<K>, s2: Set<K>): Set<K> = D.diff(s1, s2)

/// All elements as a list in unspecified order.
export fun toList<K>(s: Set<K>): List<K> = D.keys(s)

/// Build a set from a list. Duplicate elements are silently ignored.
export fun fromList<K>(hf: (K) -> Int, eqf: (K, K) -> Bool, xs: List<K>): Set<K> =
  D.fromList(hf, eqf, List.map(xs, (k: K) => { val u: Unit = (); (k, u) }))

/// Apply `f` to every element, producing a new set keyed by `hf2`/`eqf2`.
export fun map<K, K2>(s: Set<K>, f: (K) -> K2, hf2: (K2) -> Int, eqf2: (K2, K2) -> Bool): Set<K2> =
  fromList(hf2, eqf2, List.map(D.keys(s), f))

/// Left fold over all elements; iteration order is unspecified.
export fun foldl<K, B>(s: Set<K>, z: B, f: (K, B) -> B): B =
  D.foldl(s, z, (k: K, _u: Unit, acc: B) => f(k, acc))

/// Right fold over all elements; iteration order is unspecified.
export fun foldr<K, B>(s: Set<K>, z: B, f: (K, B) -> B): B =
  D.foldr(s, z, (k: K, _u: Unit, acc: B) => f(k, acc))

/// Keep only elements where `pred(k)` is `True`.
export fun filter<K>(s: Set<K>, pred: (K) -> Bool): Set<K> =
  D.filter(s, (k: K, _u: Unit) => pred(k))

/// Split into `(matching, non-matching)` based on `pred`.
export fun partition<K>(s: Set<K>, pred: (K) -> Bool): (Set<K>, Set<K>) =
  D.partition(s, (k: K, _u: Unit) => pred(k))

/// Empty `Set<String>` without passing a hash/eq pair.
export fun emptyStringSet(): Set<String> = D.emptyStringDict()

/// Empty `Set<Int>` without passing a hash/eq pair.
export fun emptyIntSet(): Set<Int> = D.emptyIntDict()

/// Single-element `Set<Int>` without passing a hash/eq pair.
export fun singletonIntSet(k: Int): Set<Int> =
  singleton(D.hashInt, D.eqInt, k)

/// Single-element `Set<String>` without passing a hash/eq pair.
export fun singletonStringSet(k: String): Set<String> =
  singleton(D.hashString, D.eqString, k)

/// Build a `Set<Int>` from a list without passing a hash/eq pair.
export fun fromIntList(xs: List<Int>): Set<Int> =
  fromList(D.hashInt, D.eqInt, xs)

/// Build a `Set<String>` from a list without passing a hash/eq pair.
export fun fromStringList(xs: List<String>): Set<String> =
  fromList(D.hashString, D.eqString, xs)
