import { Suite, group, eq } from "kestrel:test"
import { length, isEmpty, drop } from "kestrel:list"

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
  })
