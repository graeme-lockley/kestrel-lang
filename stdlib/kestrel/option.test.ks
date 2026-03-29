import { Suite, group, eq } from "kestrel:test"
import {
  getOrElse,
  withDefault,
  isNone,
  isSome,
  map,
  andThen,
  map2,
  map3,
  map4,
  map5
} from "kestrel:option"

fun double(n: Int): Int = n + n

export fun run(s: Suite): Unit =
  group(s, "option", (s1: Suite) => {
    group(s1, "construction", (sg: Suite) => {
      eq(sg, "Some(42) pattern match", match (Some(42)) { None => 0, Some(v) => v }, 42)
      eq(sg, "None pattern match", match (None) { None => 99, Some(_) => 0 }, 99)
    })

    group(s1, "matching", (sg: Suite) => {
      eq(sg, "extract Some(7)", match (Some(7)) { None => 0, Some(x) => x }, 7)
      eq(sg, "handle None", match (None) { None => 0, Some(x) => x }, 0)
    })

    group(s1, "helpers", (sg: Suite) => {
      eq(sg, "getOrElse Some(5) 0", getOrElse(Some(5), 0), 5)
      eq(sg, "getOrElse None 0", getOrElse(None, 0), 0)
      eq(sg, "getOrElse None 100", getOrElse(None, 100), 100)
      eq(sg, "withDefault", withDefault(Some(2), 9), 2)
      eq(sg, "isSome Some(1)", isSome(Some(1)), True)
      eq(sg, "isSome None", isSome(None), False)
      eq(sg, "isNone None", isNone(None), True)
      eq(sg, "isNone Some(1)", isNone(Some(1)), False)
    })

    group(s1, "polymorphic string", (sg: Suite) => {
      eq(sg, "getOrElse str", getOrElse(Some("a"), "b"), "a")
      eq(sg, "map str", getOrElse(map(Some("hi"), (t: String) => "${t}!"), ""), "hi!")
    })

    group(s1, "map andThen", (sg: Suite) => {
      eq(sg, "map Some", getOrElse(map(Some(3), double), 0), 6)
      eq(sg, "map None", getOrElse(map(None, double), 0), 0)
      eq(
        sg,
        "andThen",
        getOrElse(andThen(Some(2), (n: Int) => if (n > 0) Some(n + 1) else None), 0),
        3
      )
    })

    group(s1, "map2-5", (sg: Suite) => {
      eq(
        sg,
        "map2",
        getOrElse(map2(Some(1), Some(2), (a: Int, b: Int) => a + b), 0),
        3
      )
      eq(sg, "map2 None", getOrElse(map2(Some(1), None, (a: Int, b: Int) => a + b), 0), 0)
      eq(
        sg,
        "map3",
        getOrElse(map3(Some(1), Some(2), Some(3), (a: Int, b: Int, c: Int) => a + b + c), 0),
        6
      )
      eq(
        sg,
        "map4",
        getOrElse(map4(Some(1), Some(2), Some(3), Some(4), (a: Int, b: Int, c: Int, d: Int) => a + b + c + d), 0),
        10
      )
      eq(
        sg,
        "map5",
        getOrElse(
          map5(Some(1), Some(2), Some(3), Some(4), Some(5), (a: Int, b: Int, c: Int, d: Int, e: Int) => a + b + c + d + e),
          0
        ),
        15
      )
    })

    group(s1, "pipeline", (sg: Suite) => {
      val x = Some(3) |> map(double) |> withDefault(0)
      eq(sg, "pipe map withDefault", x, 6)
    })

    group(s1, "nested", (sg: Suite) => {
      val inner = match (Some(Some(1))) {
        None => 0,
        Some(o) => match (o) { None => 0, Some(v) => v }
      }
      eq(sg, "Some(Some(1))", inner, 1)
    })
  })
