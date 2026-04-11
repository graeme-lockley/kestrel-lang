import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as List from "kestrel:data/list"
import * as Set from "kestrel:data/set"

fun isEven(n: Int): Bool = n % 2 == 0

fun emptyInts(): List<Int> = []

export async fun run(s: Suite): Task<Unit> = {
  group(s, "kestrel:data/set", (s1: Suite) => {
    group(s1, "empty singleton", (sg: Suite) => {
      val e = Set.empty(Dict.hashInt, Dict.eqInt)
      isTrue(sg, "isEmpty", Set.isEmpty(e))
      eq(sg, "size 0", Set.size(e), 0)
      val one = Set.singletonIntSet(7)
      isTrue(sg, "singleton member", Set.member(one, 7))
      eq(sg, "singleton size", Set.size(one), 1)
      isFalse(sg, "singleton not other", Set.member(one, 0))
    })

    group(s1, "fromIntList toList", (sg: Suite) => {
      val sx = Set.fromIntList([1, 2])
      isTrue(sg, "has 1", Set.member(sx, 1))
      isFalse(sg, "no 9", Set.member(sx, 9))
      isTrue(sg, "fromIntList empty", Set.isEmpty(Set.fromIntList(emptyInts())))
      eq(sg, "toList sorted", List.sort(Set.toList(sx)), [1, 2])
    })

    group(s1, "insert remove duplicate", (sg: Suite) => {
      val s2 = Set.fromIntList([3, 4])
      isTrue(sg, "has 3", Set.member(s2, 3))
      isTrue(sg, "has 4", Set.member(s2, 4))
      eq(sg, "size 2", Set.size(s2), 2)
      val dup = Set.emptyIntSet() |> Set.insert(5) |> Set.insert(5)
      eq(sg, "duplicate insert size 1", Set.size(dup), 1)
      val rm = Set.remove(s2, 3)
      isFalse(sg, "remove not member", Set.member(rm, 3))
      isTrue(sg, "remove keeps other", Set.member(rm, 4))
      eq(sg, "remove size", Set.size(rm), 1)
    })

    group(s1, "union intersect diff", (sg: Suite) => {
      val a = Set.fromIntList([1, 2])
      val b = Set.fromIntList([2, 3])
      val u = Set.union(a, b)
      eq(sg, "union keys", List.sort(Set.toList(u)), [1, 2, 3])
      val i = Set.intersect(a, b)
      eq(sg, "intersect", List.sort(Set.toList(i)), [2])
      val d = Set.diff(a, b)
      eq(sg, "diff", List.sort(Set.toList(d)), [1])
    })

    group(s1, "foldl foldr filter", (sg: Suite) => {
      val s = Set.fromIntList([1, 2, 3])
      eq(sg, "foldl sum", Set.foldl(s, 0, (k: Int, acc: Int) => acc + k), 6)
      eq(sg, "foldr sum", Set.foldr(s, 0, (k: Int, acc: Int) => acc + k), 6)
      eq(sg, "filter evens size", Set.size(Set.filter(s, isEven)), 1)
      isTrue(sg, "filter evens member", Set.member(Set.filter(s, isEven), 2))
      val oddOnly = Set.singletonIntSet(1)
      isTrue(sg, "filter all out", Set.isEmpty(Set.filter(oddOnly, isEven)))
    })

    group(s1, "map", (sg: Suite) => {
      val s = Set.fromIntList([1, 2, 3])
      val doubled = Set.map(s, (n: Int) => n * 2, Dict.hashInt, Dict.eqInt)
      isTrue(sg, "map has doubled", Set.member(doubled, 4))
      isFalse(sg, "map not original", Set.member(doubled, 1))
      eq(sg, "map size", Set.size(doubled), 3)
    })


    group(s1, "partition", (sg: Suite) => {
      val s = Set.fromIntList([1, 2, 3, 4])
      val p = Set.partition(s, isEven)
      isTrue(sg, "evens has 2", Set.member(p.0, 2))
      isTrue(sg, "evens has 4", Set.member(p.0, 4))
      isFalse(sg, "evens no odd", Set.member(p.0, 1))
      isTrue(sg, "odds has 1", Set.member(p.1, 1))
      isTrue(sg, "odds has 3", Set.member(p.1, 3))
      isFalse(sg, "odds no even", Set.member(p.1, 2))
    })

    group(s1, "string set", (sg: Suite) => {
      val st = Set.fromStringList(["x", "y"])
      isTrue(sg, "member", Set.member(st, "x"))
      isFalse(sg, "not member", Set.member(st, "z"))
      eq(sg, "size", Set.size(st), 2)
      val st2 = Set.fromStringList(["p", "q"])
      isTrue(sg, "fromStringList", Set.member(st2, "p"))
      eq(sg, "fromStringList size", Set.size(st2), 2)
      val lone = Set.singletonStringSet("only")
      isTrue(sg, "singletonStringSet", Set.member(lone, "only"))
      eq(sg, "singletonStringSet size", Set.size(lone), 1)
    })
  })
}
