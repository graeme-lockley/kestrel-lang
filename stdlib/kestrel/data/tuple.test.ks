import { Suite, group, eq } from "kestrel:dev/test"
import { pair, first, second, mapFirst, mapSecond, mapBoth } from "kestrel:data/tuple"

fun double(n: Int): Int = n + n
fun incStr(s: String): String = "${s}!"

export async fun run(s: Suite): Task<Unit> =
  group(s, "tuple", (s1: Suite) => {
    group(s1, "pair first second", (sg: Suite) => {
      val t = pair(1, "a")
      eq(sg, "first", first(t), 1)
      eq(sg, "second", second(t), "a")
    })

    group(s1, "mapFirst mapSecond", (sg: Suite) => {
      eq(sg, "mapFirst", mapFirst((2, "x"), double), (4, "x"))
      eq(sg, "mapSecond", mapSecond((1, "hi"), incStr), (1, "hi!"))
    })

    group(s1, "mapBoth", (sg: Suite) => {
      eq(sg, "mapBoth", mapBoth((3, "z"), double, incStr), (6, "z!"))
    })

    group(s1, "pipeline", (sg: Suite) => {
      val out = pair(2, "a") |> mapFirst(double) |> mapSecond(incStr)
      eq(sg, "chain", out, (4, "a!"))
    })
  })
