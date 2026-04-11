//! HashMap-backed key-value dictionaries.
//!
//! `Dict<K, V>` wraps `java.util.HashMap` for O(1) average lookup, insert, and
//! delete. All mutating operations return a copy — the original is never modified.
//! Keys are compared by Java `.equals()`/`.hashCode()`, so `Int`, `String`, and
//! `Bool` keys work correctly out of the box.
//!
//! Functions that need to hash or compare a custom key type accept a hash function
//! `(K) -> Int` and an equality function `(K, K) -> Bool` as their first two
//! parameters (e.g. `singleton`, `fromList`). For purely `String` or `Int` keys
//! use the pre-built convenience constructors (`emptyStringDict`, `emptyIntDict`,
//! etc.) which hard-code the correct hash/eq pair.
//!
//! Pre-built hash/equality helpers exported by this module:
//! `hashInt`, `eqInt`, `hashString`, `eqString`.

import * as List from "kestrel:data/list"
import * as Str from "kestrel:data/string"

extern type JHashMap = jvm("java.util.HashMap")

extern fun jhmNew(): JHashMap =
  jvm("kestrel.runtime.KRuntime#hashMapNew()")

extern fun jhmCopy(m: JHashMap): JHashMap =
  jvm("kestrel.runtime.KRuntime#hashMapCopy(java.lang.Object)")

extern fun jhmPut<K, V>(m: JHashMap, k: K, v: V): Unit =
  jvm("kestrel.runtime.KRuntime#hashMapPut(java.lang.Object,java.lang.Object,java.lang.Object)")

extern fun jhmRemove<K>(m: JHashMap, k: K): Unit =
  jvm("kestrel.runtime.KRuntime#hashMapRemove(java.lang.Object,java.lang.Object)")

extern fun jhmGet<K, V>(m: JHashMap, k: K): V =
  jvm("kestrel.runtime.KRuntime#hashMapGet(java.lang.Object,java.lang.Object)")

extern fun jhmContains<K>(m: JHashMap, k: K): Bool =
  jvm("kestrel.runtime.KRuntime#hashMapContainsKey(java.lang.Object,java.lang.Object)")

extern fun jhmSize(m: JHashMap): Int =
  jvm("kestrel.runtime.KRuntime#hashMapSize(java.lang.Object)")

extern fun jhmKeys<K>(m: JHashMap): List<K> =
  jvm("kestrel.runtime.KRuntime#hashMapKeys(java.lang.Object)")

extern fun jhmValues<V>(m: JHashMap): List<V> =
  jvm("kestrel.runtime.KRuntime#hashMapValues(java.lang.Object)")

opaque type Dict<K, V> = JHashMap

/// Hash function for `Int` keys (identity; Java already hashes longs well).
export fun hashInt(n: Int): Int = n

/// Equality predicate for `Int` keys.
export fun eqInt(a: Int, b: Int): Bool = a == b

/// Equality predicate for `String` keys.
export fun eqString(a: String, b: String): Bool = a == b

fun djb2Step(s: String, i: Int, h: Int): Int =
  if (i >= Str.length(s)) h
  else djb2Step(s, i + 1, h * 33 + Str.codePointAt(s, i))

/// DJB2 hash for `String` keys. Suitable for use with `Dict<String, V>`.
export fun hashString(s: String): Int = djb2Step(s, 0, 5381)

/// An empty dictionary. For `String` or `Int` keys prefer `emptyStringDict` / `emptyIntDict`.
export fun empty<K, V>(): Dict<K, V> = jhmNew()

/// A dictionary containing exactly the single mapping `k -> v`.
/// `_hf` and `_eqf` are accepted for API symmetry but not used by the HashMap backend.
export fun singleton<K, V>(_hf: (K) -> Int, _eqf: (K, K) -> Bool, k: K, v: V): Dict<K, V> = {
  val m: JHashMap = jhmNew();
  jhmPut(m, k, v);
  m
}

/// Return a copy of `d` with the mapping `k -> v` added (or replaced if `k` exists).
export fun insert<K, V>(d: Dict<K, V>, k: K, v: V): Dict<K, V> = {
  val m: JHashMap = jhmCopy(d);
  jhmPut(m, k, v);
  m
}

/// Return a copy of `d` with key `k` removed; a no-op if `k` is absent.
export fun remove<K, V>(d: Dict<K, V>, k: K): Dict<K, V> = {
  val m: JHashMap = jhmCopy(d);
  jhmRemove(m, k);
  m
}

/// `Some(v)` if `k` is present in `d`; `None` otherwise.
export fun get<K, V>(d: Dict<K, V>, k: K): Option<V> =
  if (jhmContains(d, k)) Some(jhmGet(d, k)) else None

/// `True` if `k` is a key in `d`.
export fun member<K, V>(d: Dict<K, V>, k: K): Bool =
  jhmContains(d, k)

/// `True` if `d` has no entries.
export fun isEmpty<K, V>(d: Dict<K, V>): Bool =
  jhmSize(d) == 0

/// Number of key-value pairs in `d`.
export fun size<K, V>(d: Dict<K, V>): Int =
  jhmSize(d)

/// Transform the value at `k` via `f(Option<V>)`.
/// Returning `Some(v)` upserts, returning `None` removes the key.
export fun update<K, V>(d: Dict<K, V>, k: K, f: (Option<V>) -> Option<V>): Dict<K, V> =
  match (f(get(d, k))) {
    None => remove(d, k)
    Some(v) => insert(d, k, v)
  }

/// All keys in unspecified (HashMap) order.
export fun keys<K, V>(d: Dict<K, V>): List<K> =
  jhmKeys(d)

/// All values in unspecified (HashMap) order.
export fun values<K, V>(d: Dict<K, V>): List<V> =
  jhmValues(d)

/// All key-value pairs as a list in unspecified order.
export fun toList<K, V>(d: Dict<K, V>): List<(K, V)> =
  List.map(jhmKeys(d), (k: K) => (k, jhmGet(d, k)))

fun fromListLoop<K, V>(entries: List<(K, V)>, m: JHashMap): JHashMap =
  match (entries) {
    [] => m
    h :: t => {
      jhmPut(m, h.0, h.1);
      fromListLoop(t, m)
    }
  }

/// Build a dictionary from a list of `(key, value)` pairs.
/// Later entries overwrite earlier ones on duplicate keys.
/// `_hf` and `_eqf` are accepted for API symmetry but not used.
export fun fromList<K, V>(_hf: (K) -> Int, _eqf: (K, K) -> Bool, entries: List<(K, V)>): Dict<K, V> =
  fromListLoop(entries, jhmNew())

fun mapLoop<K, V, W>(ks: List<K>, d: JHashMap, m: JHashMap, f: (K, V) -> W): JHashMap =
  match (ks) {
    [] => m
    k :: t => {
      jhmPut(m, k, f(k, jhmGet(d, k)));
      mapLoop(t, d, m, f)
    }
  }

/// Transform every value with `f(key, value)`; keys are unchanged.
export fun map<K, V, W>(d: Dict<K, V>, f: (K, V) -> W): Dict<K, W> =
  mapLoop(jhmKeys(d), d, jhmNew(), f)

fun foldlLoop<K, V, B>(ks: List<K>, d: JHashMap, z: B, f: (K, V, B) -> B): B =
  match (ks) {
    [] => z
    k :: t => foldlLoop(t, d, f(k, jhmGet(d, k), z), f)
  }

/// Left fold over all key-value pairs; iteration order is unspecified.
export fun foldl<K, V, B>(d: Dict<K, V>, z: B, f: (K, V, B) -> B): B =
  foldlLoop(jhmKeys(d), d, z, f)

fun foldrLoop<K, V, B>(ks: List<K>, d: JHashMap, z: B, f: (K, V, B) -> B): B =
  match (ks) {
    [] => z
    k :: t => f(k, jhmGet(d, k), foldrLoop(t, d, z, f))
  }

/// Right fold over all key-value pairs; iteration order is unspecified.
export fun foldr<K, V, B>(d: Dict<K, V>, z: B, f: (K, V, B) -> B): B =
  foldrLoop(jhmKeys(d), d, z, f)

fun filterLoop<K, V>(ks: List<K>, d: JHashMap, m: JHashMap, pred: (K, V) -> Bool): JHashMap =
  match (ks) {
    [] => m
    k :: t => {
      val v: V = jhmGet(d, k);
      if (pred(k, v)) jhmPut(m, k, v) else ();
      filterLoop(t, d, m, pred)
    }
  }

/// Keep only entries where `pred(key, value)` is `True`.
export fun filter<K, V>(d: Dict<K, V>, pred: (K, V) -> Bool): Dict<K, V> =
  filterLoop(jhmKeys(d), d, jhmNew(), pred)

fun partitionLoop<K, V>(ks: List<K>, d: JHashMap, yes: JHashMap, no: JHashMap, pred: (K, V) -> Bool): (JHashMap, JHashMap) =
  match (ks) {
    [] => (yes, no)
    k :: t => {
      val v: V = jhmGet(d, k);
      if (pred(k, v)) jhmPut(yes, k, v) else jhmPut(no, k, v);
      partitionLoop(t, d, yes, no, pred)
    }
  }

/// Split into `(matching, non-matching)` based on `pred(key, value)`.
export fun partition<K, V>(d: Dict<K, V>, pred: (K, V) -> Bool): (Dict<K, V>, Dict<K, V>) = {
  val yes: JHashMap = jhmNew();
  val no: JHashMap = jhmNew();
  partitionLoop(jhmKeys(d), d, yes, no, pred)
}

fun unionLoop<K, V>(ks: List<K>, d1: JHashMap, m: JHashMap): JHashMap =
  match (ks) {
    [] => m
    k :: t => {
      jhmPut(m, k, jhmGet(d1, k));
      unionLoop(t, d1, m)
    }
  }

/// Merge two dictionaries; keys from `d1` take precedence over keys in `d2`.
export fun union<K, V>(d1: Dict<K, V>, d2: Dict<K, V>): Dict<K, V> =
  unionLoop(jhmKeys(d1), d1, jhmCopy(d2))

fun intersectLoop<K, V>(ks: List<K>, d2: JHashMap, m: JHashMap): JHashMap =
  match (ks) {
    [] => m
    k :: t =>
      if (jhmContains(d2, k)) {
        jhmPut(m, k, jhmGet(d2, k));
        intersectLoop(t, d2, m)
      } else
        intersectLoop(t, d2, m)
  }

/// Retain only keys present in both `d1` and `d2`; values come from `d2`.
export fun intersect<K, V>(d1: Dict<K, V>, d2: Dict<K, V>): Dict<K, V> =
  intersectLoop(jhmKeys(d1), d2, jhmNew())

fun diffLoop<K, V, B>(ks: List<K>, d1: JHashMap, d2: JHashMap, m: JHashMap): JHashMap =
  match (ks) {
    [] => m
    k :: t =>
      if (!jhmContains(d2, k)) {
        jhmPut(m, k, jhmGet(d1, k));
        diffLoop(t, d1, d2, m)
      } else
        diffLoop(t, d1, d2, m)
  }

/// Remove from `d1` all keys that are present in `d2`.
export fun diff<K, V, B>(d1: Dict<K, V>, d2: Dict<K, B>): Dict<K, V> =
  diffLoop(jhmKeys(d1), d1, d2, jhmNew())

/// Empty `Dict<String, V>` without passing a hash/eq pair.
export fun emptyStringDict<V>(): Dict<String, V> = empty()

/// Empty `Dict<Int, V>` without passing a hash/eq pair.
export fun emptyIntDict<V>(): Dict<Int, V> = empty()

/// Single-entry `Dict<Int, V>` without passing a hash/eq pair.
export fun singletonIntDict<V>(k: Int, v: V): Dict<Int, V> = {
  val m: JHashMap = jhmNew();
  jhmPut(m, k, v);
  m
}

/// Single-entry `Dict<String, V>` without passing a hash/eq pair.
export fun singletonStringDict<V>(k: String, v: V): Dict<String, V> = {
  val m: JHashMap = jhmNew();
  jhmPut(m, k, v);
  m
}

/// Build a `Dict<Int, V>` from `(Int, V)` pairs without passing a hash/eq pair.
export fun fromIntList<V>(entries: List<(Int, V)>): Dict<Int, V> =
  fromListLoop(entries, jhmNew())

/// Build a `Dict<String, V>` from `(String, V)` pairs without passing a hash/eq pair.
export fun fromStringList<V>(entries: List<(String, V)>): Dict<String, V> =
  fromListLoop(entries, jhmNew())
