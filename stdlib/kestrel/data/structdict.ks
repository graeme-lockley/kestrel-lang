//! Dictionary keyed by structural (deep-value) equality, not reference identity.
//!
//! `StructDict<K, V>` derives a canonical string representation of each key via
//! `KRuntime.formatOne` (the same serialiser used by `println`), then stores that
//! string in an underlying `Dict<String, V>`. Any key whose serialisation is
//! deterministic and unique works: ADT values, records, `Int`, `String`, `Bool`,
//! and immutable `List`.
//!
//! Limitation: mutable `Array<T>` must NOT be used as keys because its
//! serialisation is identity-based, not structural.
//!
//! When to prefer `StructDict` over `Dict`:
//! - Key type is a composite record or ADT value.
//! - You do not want to write a custom hash/eq pair.
//! When to prefer `Dict`:
//! - Keys are primitive (`Int`, `String`) and performance matters.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as SD from "kestrel:data/structdict"
//!
//! type UserKey = { org: String, id: Int }
//! val d0 = SD.empty()
//! val d1 = SD.insert(d0, { org = "acme", id = 10 }, "alice")
//! val d2 = SD.insert(d1, { org = "acme", id = 11 }, "bob")
//! val who = SD.get(d2, { org = "acme", id = 10 })
//! val names = SD.values(d2)
//! ```
//!

import * as List from "kestrel:data/list"
import * as Dict from "kestrel:data/dict"

extern fun structKey<A>(v: A): String =
  jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")

// Backing: a pair (vals: Dict<String, V>, origKeys: Dict<String, K>)
// origKeys preserves the original key so keys()/toList() can return K not String.

opaque type StructDict<K, V> = (Dict<String, V>, Dict<String, K>)

/// An empty `StructDict`.
export fun empty<K, V>(): StructDict<K, V> =
  (Dict.empty(), Dict.empty())

/// A `StructDict` containing the single mapping `k -> v`.
export fun singleton<K, V>(k: K, v: V): StructDict<K, V> =
  insert(empty(), k, v)

/// Return a copy of `d` with the mapping `k -> v` added or replaced.
export fun insert<K, V>(d: StructDict<K, V>, k: K, v: V): StructDict<K, V> = {
  val sk = structKey(k);
  (Dict.insert(d.0, sk, v), Dict.insert(d.1, sk, k))
}

/// Return a copy of `d` with key `k` removed (no-op if absent).
export fun remove<K, V>(d: StructDict<K, V>, k: K): StructDict<K, V> = {
  val sk = structKey(k);
  (Dict.remove(d.0, sk), Dict.remove(d.1, sk))
}

/// `Some(v)` if `k` is present; `None` otherwise.
export fun get<K, V>(d: StructDict<K, V>, k: K): Option<V> =
  Dict.get(d.0, structKey(k))

/// `True` if `k` is a key in `d`.
export fun member<K, V>(d: StructDict<K, V>, k: K): Bool =
  Dict.member(d.0, structKey(k))

/// Number of key-value pairs.
export fun size<K, V>(d: StructDict<K, V>): Int =
  Dict.size(d.0)

/// `True` if `d` has no entries.
export fun isEmpty<K, V>(d: StructDict<K, V>): Bool =
  Dict.isEmpty(d.0)

/// All keys in unspecified order. Original key values (not their string encodings) are returned.
export fun keys<K, V>(d: StructDict<K, V>): List<K> =
  List.filterMap(Dict.keys(d.1), (sk: String) => Dict.get(d.1, sk))

/// All values in unspecified order.
export fun values<K, V>(d: StructDict<K, V>): List<V> =
  Dict.values(d.0)

/// All key-value pairs as a list in unspecified order.
export fun toList<K, V>(d: StructDict<K, V>): List<(K, V)> =
  List.filterMap(Dict.keys(d.1), (sk: String) =>
    match (Dict.get(d.1, sk)) {
      None => None
      Some(k) => match (Dict.get(d.0, sk)) {
        None => None
        Some(v) => Some((k, v))
      }
    })

/// Build a `StructDict` from a list of `(key, value)` pairs.
/// Later entries overwrite earlier ones on duplicate structural keys.
export fun fromList<K, V>(entries: List<(K, V)>): StructDict<K, V> =
  List.foldl(entries, empty(), (acc: StructDict<K, V>, kv: (K, V)) => insert(acc, kv.0, kv.1))

/// Transform every value with `f(key, value)`; keys are unchanged.
export fun map<K, V, W>(d: StructDict<K, V>, f: (K, V) -> W): StructDict<K, W> =
  List.foldl(toList(d), empty(), (acc: StructDict<K, W>, kv: (K, V)) => insert(acc, kv.0, f(kv.0, kv.1)))

/// Keep only entries where `pred(key, value)` is `True`.
export fun filter<K, V>(d: StructDict<K, V>, pred: (K, V) -> Bool): StructDict<K, V> =
  List.foldl(toList(d), empty(), (acc: StructDict<K, V>, kv: (K, V)) =>
    if (pred(kv.0, kv.1)) insert(acc, kv.0, kv.1) else acc)

/// Left fold over all key-value pairs; iteration order is unspecified.
export fun foldl<K, V, B>(d: StructDict<K, V>, z: B, f: (K, V, B) -> B): B =
  List.foldl(toList(d), z, (acc: B, kv: (K, V)) => f(kv.0, kv.1, acc))

/// Merge two dicts; keys already in `a` are not overwritten by `b`.
export fun union<K, V>(a: StructDict<K, V>, b: StructDict<K, V>): StructDict<K, V> =
  List.foldl(toList(b), a, (acc: StructDict<K, V>, kv: (K, V)) =>
    if (member(acc, kv.0)) acc else insert(acc, kv.0, kv.1))

/// Remove from `a` all keys that are present in `b`.
export fun diff<K, V>(a: StructDict<K, V>, b: StructDict<K, V>): StructDict<K, V> =
  filter(a, (k: K, _v: V) => !member(b, k))

/// Keep only keys present in both `a` and `b`; values come from `a`.
export fun intersect<K, V>(a: StructDict<K, V>, b: StructDict<K, V>): StructDict<K, V> =
  filter(a, (k: K, _v: V) => member(b, k))
