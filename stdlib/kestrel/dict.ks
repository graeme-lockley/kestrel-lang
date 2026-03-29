// kestrel:dict — association-list dictionaries with embedded hash + equality (pipe-friendly).

import * as Str from "kestrel:string"
import * as List from "kestrel:list"

opaque type Dict<K, V> = { hash: (K) -> Int, eq: (K, K) -> Bool, entries: List<(K, V)> }

fun mkDict<K, V>(hf: (K) -> Int, eqf: (K, K) -> Bool, entries: List<(K, V)>): Dict<K, V> =
  { hash = hf, eq = eqf, entries = entries }

export fun hashInt(n: Int): Int = n

export fun eqInt(a: Int, b: Int): Bool = a == b

export fun eqString(a: String, b: String): Bool = a == b

fun djb2Step(s: String, i: Int, h: Int): Int =
  if (i >= Str.length(s)) h
  else djb2Step(s, i + 1, h * 33 + Str.codePointAt(s, i))

export fun hashString(s: String): Int = djb2Step(s, 0, 5381)

export fun empty<K, V>(hf: (K) -> Int, eqf: (K, K) -> Bool): Dict<K, V> =
  mkDict(hf, eqf, [])

export fun singleton<K, V>(hf: (K) -> Int, eqf: (K, K) -> Bool, k: K, v: V): Dict<K, V> =
  mkDict(hf, eqf, [(k, v)])

fun withoutKey<K, V>(entries: List<(K, V)>, eqf: (K, K) -> Bool, k: K): List<(K, V)> =
  List.filter(entries, (e: (K, V)) => !eqf(k, e.0))

export fun insert<K, V>(d: Dict<K, V>, k: K, v: V): Dict<K, V> =
  mkDict(d.hash, d.eq, (k, v) :: withoutKey(d.entries, d.eq, k))

export fun remove<K, V>(d: Dict<K, V>, k: K): Dict<K, V> =
  mkDict(d.hash, d.eq, withoutKey(d.entries, d.eq, k))

fun getLoop<K, V>(entries: List<(K, V)>, eqf: (K, K) -> Bool, k: K): Option<V> =
  match (entries) {
    [] => None
    h :: t =>
      if (eqf(k, h.0)) Some(h.1) else getLoop(t, eqf, k)
  }

export fun get<K, V>(d: Dict<K, V>, k: K): Option<V> =
  getLoop(d.entries, d.eq, k)

export fun member<K, V>(d: Dict<K, V>, k: K): Bool =
  match (get(d, k)) {
    None => False
    Some(_) => True
  }

export fun isEmpty<K, V>(d: Dict<K, V>): Bool =
  match (d.entries) {
    [] => True
    _ => False
  }

export fun size<K, V>(d: Dict<K, V>): Int =
  List.length(d.entries)

export fun update<K, V>(d: Dict<K, V>, k: K, f: (Option<V>) -> Option<V>): Dict<K, V> =
  match (f(get(d, k))) {
    None => mkDict(d.hash, d.eq, withoutKey(d.entries, d.eq, k))
    Some(v) => mkDict(d.hash, d.eq, (k, v) :: withoutKey(d.entries, d.eq, k))
  }

export fun keys<K, V>(d: Dict<K, V>): List<K> =
  List.map(d.entries, (e: (K, V)) => e.0)

export fun values<K, V>(d: Dict<K, V>): List<V> =
  List.map(d.entries, (e: (K, V)) => e.1)

export fun toList<K, V>(d: Dict<K, V>): List<(K, V)> =
  d.entries

fun fromListLoop<K, V>(entries: List<(K, V)>, acc: Dict<K, V>): Dict<K, V> =
  match (entries) {
    [] => acc
    h :: t => fromListLoop(t, insert(acc, h.0, h.1))
  }

export fun fromList<K, V>(hf: (K) -> Int, eqf: (K, K) -> Bool, entries: List<(K, V)>): Dict<K, V> =
  fromListLoop(entries, empty(hf, eqf))

export fun map<K, V, W>(d: Dict<K, V>, f: (K, V) -> W): Dict<K, W> =
  mkDict(d.hash, d.eq, List.map(d.entries, (e: (K, V)) => (e.0, f(e.0, e.1))))

export fun foldl<K, V, B>(d: Dict<K, V>, z: B, f: (K, V, B) -> B): B =
  List.foldl(d.entries, z, (acc: B, e: (K, V)) => f(e.0, e.1, acc))

export fun foldr<K, V, B>(d: Dict<K, V>, z: B, f: (K, V, B) -> B): B =
  List.foldr(d.entries, z, (e: (K, V), acc: B) => f(e.0, e.1, acc))

export fun filter<K, V>(d: Dict<K, V>, pred: (K, V) -> Bool): Dict<K, V> =
  mkDict(d.hash, d.eq, List.filter(d.entries, (e: (K, V)) => pred(e.0, e.1)))

fun partitionLoop<K, V>(entries: List<(K, V)>, pred: (K, V) -> Bool, t: List<(K, V)>, f: List<(K, V)>): (List<(K, V)>, List<(K, V)>) =
  match (entries) {
    [] => (t, f)
    h :: rest =>
      if (pred(h.0, h.1)) partitionLoop(rest, pred, h :: t, f)
      else partitionLoop(rest, pred, t, h :: f)
  }

export fun partition<K, V>(d: Dict<K, V>, pred: (K, V) -> Bool): (Dict<K, V>, Dict<K, V>) = {
  val parts = partitionLoop(d.entries, pred, [], []);
  (mkDict(d.hash, d.eq, List.reverse(parts.0)), mkDict(d.hash, d.eq, List.reverse(parts.1)))
}

fun unionLoop<K, V>(acc: Dict<K, V>, entries: List<(K, V)>): Dict<K, V> =
  match (entries) {
    [] => acc
    h :: t =>
      if (member(acc, h.0)) 
        unionLoop(acc, t)
      else 
        unionLoop(insert(acc, h.0, h.1), t)
  }

export fun union<K, V>(d1: Dict<K, V>, d2: Dict<K, V>): Dict<K, V> =
  unionLoop(d1, d2.entries)

fun intersectLoop<K, V>(d2: Dict<K, V>, entries: List<(K, V)>, acc: Dict<K, V>): Dict<K, V> =
  match (entries) {
    [] => acc
    h :: t =>
      if (member(d2, h.0)) {
        val v2 = match (get(d2, h.0)) {
          None => h.1
          Some(x) => x
        }
        intersectLoop(d2, t, insert(acc, h.0, v2))
      } else intersectLoop(d2, t, acc)
  }

export fun intersect<K, V>(d1: Dict<K, V>, d2: Dict<K, V>): Dict<K, V> =
  intersectLoop(d2, d1.entries, empty(d1.hash, d1.eq))

fun diffLoop<K, V, B>(d2: Dict<K, B>, entries: List<(K, V)>, acc: Dict<K, V>): Dict<K, V> =
  match (entries) {
    [] => acc
    h :: t =>
      if (member(d2, h.0)) diffLoop(d2, t, acc)
      else diffLoop(d2, t, insert(acc, h.0, h.1))
  }

export fun diff<K, V, B>(d1: Dict<K, V>, d2: Dict<K, B>): Dict<K, V> =
  diffLoop(d2, d1.entries, empty(d1.hash, d1.eq))

export fun emptyStringDict<V>(): Dict<String, V> =
  empty(hashString, eqString)

export fun emptyIntDict<V>(): Dict<Int, V> =
  empty(hashInt, eqInt)

export fun singletonIntDict<V>(k: Int, v: V): Dict<Int, V> =
  singleton(hashInt, eqInt, k, v)

export fun singletonStringDict<V>(k: String, v: V): Dict<String, V> =
  singleton(hashString, eqString, k, v)

export fun fromIntList<V>(entries: List<(Int, V)>): Dict<Int, V> =
  fromList(hashInt, eqInt, entries)

export fun fromStringList<V>(entries: List<(String, V)>): Dict<String, V> =
  fromList(hashString, eqString, entries)
