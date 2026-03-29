import { Suite, group, eq } from "kestrel:test"
import { getOrElse as optGet } from "kestrel:option"
import {
  getOrElse,
  withDefault,
  isOk,
  isErr,
  map,
  mapError,
  andThen,
  map2,
  map3,
  toOption,
  fromOption
} from "kestrel:result"

fun double(n: Int): Int = n + n

export fun run(s: Suite): Unit =
  group(s, "result", (s1: Suite) => {
    group(s1, "construction", (sg: Suite) => {
      eq(sg, "Ok(42) pattern match", match (Ok(42)) { Err(_) => 0, Ok(v) => v }, 42)
      eq(sg, "Err(1) pattern match", match (Err(1)) { Err(e) => e, Ok(_) => 0 }, 1)
    })

    group(s1, "matching", (sg: Suite) => {
      eq(sg, "extract Ok(7)", match (Ok(7)) { Err(_) => 0, Ok(x) => x }, 7)
      eq(sg, "extract Err(3)", match (Err(3)) { Err(e) => e, Ok(_) => 0 }, 3)
    })

    group(s1, "helpers", (sg: Suite) => {
      eq(sg, "getOrElse Ok(5) 0", getOrElse(Ok(5), 0), 5)
      eq(sg, "getOrElse Err(1) 0", getOrElse(Err(1), 0), 0)
      eq(sg, "getOrElse Err(1) 100", getOrElse(Err(1), 100), 100)
      eq(sg, "withDefault", withDefault(Ok(2), 9), 2)
      eq(sg, "isOk Ok(1)", isOk(Ok(1)), True)
      eq(sg, "isOk Err(1)", isOk(Err(1)), False)
      eq(sg, "isErr Err(1)", isErr(Err(1)), True)
      eq(sg, "isErr Ok(1)", isErr(Ok(1)), False)
    })

    group(s1, "polymorphic (distinct T and E)", (sg: Suite) => {
      eq(sg, "getOrElse Ok string", getOrElse(Ok("hi"), "no"), "hi")
      eq(sg, "getOrElse Err string default", getOrElse(Err("bad"), "no"), "no")
      eq(sg, "isOk Ok string", isOk(Ok("a")), True)
      eq(sg, "isErr Err int payload", isErr(Err(99)), True)
    })

    group(s1, "map mapError andThen", (sg: Suite) => {
      eq(sg, "map Ok", getOrElse(map(Ok(3), double), 0), 6)
      eq(sg, "map Err", getOrElse(map(Err(1), double), 0), 0)
      eq(sg, "mapError Err", match (mapError(Err(1), (e: Int) => e + 1)) { Ok(_) => 0, Err(e) => e }, 2)
      eq(sg, "mapError Ok", getOrElse(mapError(Ok(5), (e: Int) => e), 0), 5)
      eq(sg, "andThen Ok", getOrElse(andThen(Ok(2), (n: Int) => Ok(n + 1)), 0), 3)
      eq(sg, "andThen Err", getOrElse(andThen(Err(9), (n: Int) => Ok(n)), 0), 0)
    })

    group(s1, "map2 map3", (sg: Suite) => {
      eq(sg, "map2 both Ok", getOrElse(map2(Ok(1), Ok(2), (a: Int, b: Int) => a + b), 0), 3)
      eq(sg, "map2 first Err", isErr(map2(Err(1), Ok(2), (a: Int, b: Int) => a + b)), True)
      eq(
        sg,
        "map3",
        getOrElse(map3(Ok(1), Ok(2), Ok(3), (a: Int, b: Int, c: Int) => a + b + c), 0),
        6
      )
    })

    group(s1, "option interop", (sg: Suite) => {
      eq(sg, "toOption Ok", optGet(toOption(Ok(7)), 0), 7)
      eq(sg, "toOption Err", optGet(toOption(Err(1)), 0), 0)
      eq(sg, "fromOption Some", getOrElse(fromOption(Some(4), "bad"), 0), 4)
      eq(sg, "fromOption None", match (fromOption(None, 404)) { Ok(_) => 0, Err(e) => e }, 404)
    })

    group(s1, "pipeline", (sg: Suite) => {
      val v = Ok(3) |> map(double) |> withDefault(0)
      eq(sg, "pipe", v, 6)
    })
  })
