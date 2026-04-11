// kestrel:data/structdict — Dict with structural (value) equality keys.
//
// Keys are compared by structural equality via formatOne serialisation.
// Works correctly for ADT values, records, Int, String, Bool, List.
// Does NOT support mutable Array<T> as keys (identity-based, not structural).

import * as List from "kestrel:data/list"
import * as Dict from "kestrel:data/dict"

extern fun structKey<A>(v: A): String =
  jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")

// Backing: a pair (vals: Dict<String, V>, origKeys: Dict<String, K>)
// origKeys preserves the original key so keys()/toList() can return K not String.

opaque type StructDict<K, V> = (Dict<String, V>, Dict<String, K>)

export fun empty<K, V>(): StructDict<K, V> =
  (Dict.empty(), Dict.empty())

export fun singleton<K, V>(k: K, v: V): StructDict<K, V> =
  insert(empty(), k, v)

export fun insert<K, V>(d: StructDict<K, V>, k: K, v: V): StructDict<K, V> = {
  val sk = structKey(k);
  (Dict.insert(d.0, sk, v), Dict.insert(d.1, sk, k))
}

export fun remove<K, V>(d: StructDict<K, V>, k: K): StructDict<K, V> = {
  val sk = structKey(k);
  (Dict.remove(d.0, sk), Dict.remove(d.1, sk))
}

export fun get<K, V>(d: StructDict<K, V>, k: K): Option<V> =
  Dict.get(d.0, structKey(k))

export fun member<K, V>(d: StructDict<K, V>, k: K): Bool =
  Dict.member(d.0, structKey(k))

export fun size<K, V>(d: StructDict<K, V>): Int =
  Dict.size(d.0)

export fun isEmpty<K, V>(d: StructDict<K, V>): Bool =
  Dict.isEmpty(d.0)

export fun keys<K, V>(d: StructDict<K, V>): List<K> =
  List.filterMap(Dict.keys(d.1), (sk: String) => Dict.get(d.1, sk))

export fun values<K, V>(d: StructDict<K, V>): List<V> =
  Dict.values(d.0)

export fun toList<K, V>(d: StructDict<K, V>): List<(K, V)> =
  List.filterMap(Dict.keys(d.1), (sk: String) =>
    match (Dict.get(d.1, sk)) {
      None => None
      Some(k) => match (Dict.get(d.0, sk)) {
        None => None
        Some(v) => Some((k, v))
      }
    })

export fun fromList<K, V>(entries: List<(K, V)>): StructDict<K, V> =
  List.foldl(entries, empty(), (acc: StructDict<K, V>, kv: (K, V)) => insert(acc, kv.0, kv.1))

export fun map<K, V, W>(d: StructDict<K, V>, f: (K, V) -> W): StructDict<K, W> =
  List.foldl(toList(d), empty(), (acc: StructDict<K, W>, kv: (K, V)) => insert(acc, kv.0, f(kv.0, kv.1)))

export fun filter<K, V>(d: StructDict<K, V>, pred: (K, V) -> Bool): StructDict<K, V> =
  List.foldl(toList(d), empty(), (acc: StructDict<K, V>, kv: (K, V)) =>
    if (pred(kv.0, kv.1)) insert(acc, kv.0, kv.1) else acc)

export fun foldl<K, V, B>(d: StructDict<K, V>, z: B, f: (K, V, B) -> B): B =
  List.foldl(toList(d), z, (acc: B, kv: (K, V)) => f(kv.0, kv.1, acc))

export fun union<K, V>(a: StructDict<K, V>, b: StructDict<K, V>): StructDict<K, V> =
  List.foldl(toList(b), a, (acc: StructDict<K, V>, kv: (K, V)) =>
    if (member(acc, kv.0)) acc else insert(acc, kv.0, kv.1))

export fun diff<K, V>(a: StructDict<K, V>, b: StructDict<K, V>): StructDict<K, V> =
  filter(a, (k: K, _v: V) => !member(b, k))

export fun intersect<K, V>(a: StructDict<K, V>, b: StructDict<K, V>): StructDict<K, V> =
  filter(a, (k: K, _v: V) => member(b, k))
