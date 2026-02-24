import { Suite, group, eq } from "kestrel:test"

fun double(x: Int): Int = x * 2
fun add1(x: Int): Int = x + 1
fun triple(x: Int): Int = x * 3

export fun run(s: Suite): Unit =
  group(s, "pipes", (s1: Suite) => {
    group(s1, "forward pipe", (sg: Suite) => {
      eq(sg, "3 |> double", 3 |> double, 6)
      eq(sg, "double <| 5", double <| 5, 10)
    })

    group(s1, "chained", (sg: Suite) => {
      eq(sg, "3 |> double |> add1", 3 |> double |> add1, 7)
      eq(sg, "2 |> double |> add1 |> triple", 2 |> double |> add1 |> triple, 15)
    })

    group(s1, "backward pipe", (sg: Suite) => {
      eq(sg, "double <| 5", double <| 5, 10)
      eq(sg, "triple <| 1 + 2", triple <| 1 + 2, 9)
    })
  })
