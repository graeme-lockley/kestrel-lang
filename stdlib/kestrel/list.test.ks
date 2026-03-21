import { Suite, group, eq } from "kestrel:test"
import { length, isEmpty, drop, map, filter, foldl, reverse } from "kestrel:list"

fun inc(n: Int): Int = n + 1

fun isEven(n: Int): Bool = n % 2 == 0

fun sumAcc(acc: Int, x: Int): Int = acc + x

export fun run(s: Suite): Unit =
  group(s, "list", (s1: Suite) => {    
    group(s1, "length", (sg: Suite) => {
      eq(sg, "empty", length([]), 0)
      eq(sg, "singleton", length([1]), 1)
      eq(sg, "multi-element", length([1, 2, 3]), 3)
    })

    group(s1, "isEmpty", (sg: Suite) => {
      eq(sg, "empty", isEmpty([]), True)
      eq(sg, "non-empty", isEmpty([1, 2, 3]), False)
      eq(sg, "singleton", isEmpty(["Hello"]), False)
    })

    group(s1, "drop", (sg: Suite) => {
      eq(sg, "drop 0", drop(0, [1, 2, 3]), [1, 2, 3])
      eq(sg, "drop negative", drop(-1, [1, 2, 3]), [1, 2, 3])
      eq(sg, "drop 1", drop(1, [1, 2, 3]), [2, 3])
      eq(sg, "drop 2", drop(2, ["a", "b", "c"]), ["c"])
      eq(sg, "drop 3", drop(3, [1, 2, 3]), [])
      eq(sg, "drop past length", drop(10, [1, 2, 3]), [])
      eq(sg, "drop from empty", drop(2, []), [])
    })

    group(s1, "map", (sg: Suite) => {
      eq(sg, "empty", map([], inc), [])
      eq(sg, "ints", map([1, 2, 3], inc), [2, 3, 4])
    })

    group(s1, "filter", (sg: Suite) => {
      eq(sg, "empty", filter([], isEven), [])
      eq(sg, "evens", filter([1, 2, 3, 4], isEven), [2, 4])
    })

    group(s1, "foldl", (sg: Suite) => {
      eq(sg, "sum", foldl([1, 2, 3], 0, sumAcc), 6)
      eq(sg, "empty", foldl([], 0, sumAcc), 0)
    })

    group(s1, "reverse", (sg: Suite) => {
      eq(sg, "empty", reverse([]), [])
      eq(sg, "list", reverse([1, 2, 3]), [3, 2, 1])
    })
  })
