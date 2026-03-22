// kestrel:set — sets as opaque Set<E> (= Dict<E, Unit>), pipe-friendly.

import * as List from "kestrel:list"
import * as D from "kestrel:dict"
import { Dict } from "kestrel:dict"

// Parens: parser otherwise treats `= Dict<...>` as starting an ADT body (uppercase ident + `<`).
opaque type Set<E> = (Dict<E, Unit>)

export fun empty<K>(hf: (K) -> Int, eqf: (K, K) -> Bool): Set<K> = D.empty(hf, eqf)

export fun singleton<K>(hf: (K) -> Int, eqf: (K, K) -> Bool, k: K): Set<K> = {
  val u: Unit = ()
  D.singleton(hf, eqf, k, u)
}

export fun insert<K>(s: Set<K>, k: K): Set<K> = {
  val u: Unit = ()
  D.insert(s, k, u)
}

export fun remove<K>(s: Set<K>, k: K): Set<K> = D.remove(s, k)

export fun member<K>(s: Set<K>, k: K): Bool = D.member(s, k)

export fun isEmpty<K>(s: Set<K>): Bool = D.isEmpty(s)

export fun size<K>(s: Set<K>): Int = D.size(s)

export fun union<K>(s1: Set<K>, s2: Set<K>): Set<K> = D.union(s1, s2)

export fun intersect<K>(s1: Set<K>, s2: Set<K>): Set<K> = D.intersect(s1, s2)

export fun diff<K>(s1: Set<K>, s2: Set<K>): Set<K> = D.diff(s1, s2)

export fun toList<K>(s: Set<K>): List<K> = D.keys(s)

export fun fromList<K>(hf: (K) -> Int, eqf: (K, K) -> Bool, xs: List<K>): Set<K> =
  D.fromList(hf, eqf, List.map(xs, (k: K) => { val u: Unit = (); (k, u) }))

export fun map<K, K2>(s: Set<K>, f: (K) -> K2, hf2: (K2) -> Int, eqf2: (K2, K2) -> Bool): Set<K2> =
  fromList(hf2, eqf2, List.map(D.keys(s), f))

export fun foldl<K, B>(s: Set<K>, z: B, f: (K, B) -> B): B =
  D.foldl(s, z, (k: K, _u: Unit, acc: B) => f(k, acc))

export fun foldr<K, B>(s: Set<K>, z: B, f: (K, B) -> B): B =
  D.foldr(s, z, (k: K, _u: Unit, acc: B) => f(k, acc))

export fun filter<K>(s: Set<K>, pred: (K) -> Bool): Set<K> =
  D.filter(s, (k: K, _u: Unit) => pred(k))

export fun partition<K>(s: Set<K>, pred: (K) -> Bool): (Set<K>, Set<K>) =
  D.partition(s, (k: K, _u: Unit) => pred(k))

export fun emptyStringSet(): Set<String> = D.emptyStringDict()

export fun emptyIntSet(): Set<Int> = D.emptyIntDict()

export fun singletonIntSet(k: Int): Set<Int> =
  singleton(D.hashInt, D.eqInt, k)

export fun singletonStringSet(k: String): Set<String> =
  singleton(D.hashString, D.eqString, k)

export fun fromIntList(xs: List<Int>): Set<Int> =
  fromList(D.hashInt, D.eqInt, xs)

export fun fromStringList(xs: List<String>): Set<String> =
  fromList(D.hashString, D.eqString, xs)
