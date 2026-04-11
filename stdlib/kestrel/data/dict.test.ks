import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Opt from "kestrel:data/option"

export async fun run(s: Suite): Task<Unit> = {
  group(s, "dict", (s1: Suite) => {
    group(s1, "int core", (sg: Suite) => {
      val d0 = Dict.emptyIntDict()
      isTrue(sg, "isEmpty", Dict.isEmpty(d0))
      val d1 = Dict.insert(d0, 1, 10)
      eq(sg, "get hit", Opt.getOrElse(Dict.get(d1, 1), 0), 10)
      val d2 = Dict.insert(d1, 2, 20)
      eq(sg, "size", Dict.size(d2), 2)
      val d3 = Dict.remove(d2, 1)
      isFalse(sg, "remove", Dict.member(d3, 1))
      val d4 = Dict.update(d3, 2, (o: Option<Int>) =>
        match (o) {
          None => None
          Some(v) => Some(v + 1)
        }
      )
      eq(sg, "update", Opt.getOrElse(Dict.get(d4, 2), 0), 21)
    })

    group(s1, "int algebra", (sg: Suite) => {
      val a =
        Dict.emptyIntDict()
          |> Dict.insert(1, 1)
          |> Dict.insert(2, 2)

      val b =
        Dict.emptyIntDict()
          |> Dict.insert(2, 99)
          |> Dict.insert(3, 3)

      val u = Dict.union(a, b)
      eq(sg, "union left 2", Opt.getOrElse(Dict.get(u, 2), 0), 2)
      val i = Dict.intersect(a, b)
      eq(sg, "intersect val from second", Opt.getOrElse(Dict.get(i, 2), 0), 99)
      val di = Dict.diff(a, b)
      eq(sg, "diff keeps 1", Opt.getOrElse(Dict.get(di, 1), 0), 1)
    })

    group(s1, "int fold filter", (sg: Suite) => {
      val d =
        Dict.emptyIntDict()
          |> Dict.insert(1, 2)
          |> Dict.insert(3, 4)

      eq(sg, "foldl", Dict.foldl(d, 0, (_k: Int, v: Int, acc: Int) => acc + v), 6)
      eq(sg, "filter", Dict.size(Dict.filter(d, (_k: Int, v: Int) => v > 2)), 1)
    })

    group(s1, "singletonIntDict", (sg: Suite) => {
      val one = Dict.singletonIntDict(7, 70)
      eq(sg, "get 7", Opt.getOrElse(Dict.get(one, 7), 0), 70)
      eq(sg, "size 1", Dict.size(one), 1)
    })

    group(s1, "string pipe and fromStringList", (sg: Suite) => {
      val d =
        Dict.emptyStringDict()
          |> Dict.insert("a", 1)
          |> Dict.insert("b", 2)
      eq(sg, "pipe get a", Opt.getOrElse(Dict.get(d, "a"), 0), 1)
      val d2 = Dict.fromStringList([("x", 9), ("y", 8)])
      eq(sg, "fromStringList x", Opt.getOrElse(Dict.get(d2, "x"), 0), 9)
      val lone = Dict.singletonStringDict("only", 42)
      eq(sg, "singletonStringDict", Opt.getOrElse(Dict.get(lone, "only"), 0), 42)
      eq(sg, "singletonStringDict size", Dict.size(lone), 1)
    })

    group(s1, "fromIntList", (sg: Suite) => {
      val d = Dict.fromIntList([(5, 50), (6, 60)])
      eq(sg, "get", Opt.getOrElse(Dict.get(d, 5), 0), 50)
      eq(sg, "size", Dict.size(d), 2)
    })
  })
}
