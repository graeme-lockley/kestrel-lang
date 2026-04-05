import { Suite, group, eq, isTrue } from "kestrel:test"
import { new as newArr, get, set, push, length, fromList, toList } from "kestrel:array"
import { map } from "kestrel:data/list"

export async fun run(s: Suite): Task<Unit> =
  group(s, "array", (s1: Suite) => {
    group(s1, "new", (sg: Suite) => {
      val a = newArr()
      eq(sg, "empty length", length(a), 0)
    });

    group(s1, "push and length", (sg: Suite) => {
      val a = newArr()
      push(a, 10)
      push(a, 20)
      push(a, 30)
      eq(sg, "length after 3 pushes", length(a), 3)
    });

    group(s1, "get", (sg: Suite) => {
      val a = newArr()
      push(a, 100)
      push(a, 200)
      eq(sg, "get 0", get(a, 0), 100)
      eq(sg, "get 1", get(a, 1), 200)
    });

    group(s1, "set", (sg: Suite) => {
      val a = newArr()
      push(a, 1)
      push(a, 2)
      push(a, 3)
      set(a, 1, 99)
      eq(sg, "set middle", get(a, 1), 99)
      eq(sg, "set leaves others", get(a, 0), 1)
      eq(sg, "set leaves tail", get(a, 2), 3)
    });

    group(s1, "fromList", (sg: Suite) => {
      val a = fromList([1, 2, 3])
      eq(sg, "fromList length", length(a), 3)
      eq(sg, "fromList get 0", get(a, 0), 1)
      eq(sg, "fromList get 2", get(a, 2), 3)
    });

    group(s1, "toList", (sg: Suite) => {
      val lst = [10, 20, 30, 40]
      val a = fromList(lst)
      val xs = toList(a)
      eq(sg, "toList", xs, lst)
    });

    group(s1, "fromList/toList round-trip", (sg: Suite) => {
      val orig = [5, 6, 7, 8]
      val roundtrip = toList(fromList(orig))
      eq(sg, "round-trip", roundtrip, orig)
    });

    group(s1, "string elements", (sg: Suite) => {
      val a = newArr()
      push(a, "hello")
      push(a, "world")
      eq(sg, "string get 0", get(a, 0), "hello")
      eq(sg, "string get 1", get(a, 1), "world")
    });
  })
