import { Suite, group, eq } from "kestrel:test"

fun boolToInt(b: Bool): Int = match (b) { True => 1, False => 0 }

fun boolToString(b: Bool): String = match (b) { False => "False", True => "True" }

fun fromOption(o: Option<Int>): Int = match (o) {
  None => 0,
  Some { value = x } => x
}

fun fromResult(r: Result<Int, Int>): Int = match (r) {
  Err { value = _ } => 0 - 1,
  Ok { value = x } => x
}

fun sumListMatch(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => h + sumListMatch(t) }

export fun run(s: Suite): Unit =
  group(s, "match", (s1: Suite) => {
    group(s1, "boolean patterns", (sg: Suite) => {
      eq(sg, "boolToInt(True)", boolToInt(True), 1)
      eq(sg, "boolToInt(False)", boolToInt(False), 0)
      eq(sg, "boolToString(True)", boolToString(True), "True")
      eq(sg, "boolToString(False)", boolToString(False), "False")
      eq(sg, "match True => 10", match (True) { True => 10, False => 20 }, 10)
      eq(sg, "match False => 40", match (False) { True => 30, False => 40 }, 40)
    })

    group(s1, "wildcard pattern", (sg: Suite) => {
      eq(sg, "True => default", match (True) { _ => 99 }, 99)
      eq(sg, "False => default", match (False) { _ => 77 }, 77)
      eq(sg, "42 => default", match (42) { x => x + 1 }, 43)
    })

    group(s1, "variable pattern", (sg: Suite) => {
      eq(sg, "x => x + 1", match (10) { x => x + 1 }, 11)
      eq(sg, "bind and use", match (5) { n => n * n }, 25)
    })

    group(s1, "list patterns", (sg: Suite) => {
      val emptySum = match ([]) { [] => 0, h :: t => h }
      eq(sg, "empty list", emptySum, 0)
      val consSum = match ([1, 2, 3]) { [] => 0, h :: t => h }
      eq(sg, "cons head", consSum, 1)
      eq(sg, "list sum", sumListMatch([1, 2, 3]), 6)
    })

    group(s1, "option patterns", (sg: Suite) => {
      eq(sg, "fromOption Some(7)", fromOption(Some(7)), 7)
      eq(sg, "fromOption None", fromOption(None), 0)
      eq(sg, "match Some(10)", match (Some(10)) { None => 0, Some { value = v } => v }, 10)
      eq(sg, "match None", match (None) { None => 99, Some { value = _ } => 0 }, 99)
    })

    group(s1, "result patterns", (sg: Suite) => {
      eq(sg, "fromResult Ok(42)", fromResult(Ok(42)), 42)
      eq(sg, "fromResult Err(1)", fromResult(Err(1)), 0 - 1)
      eq(sg, "match Ok(5)", match (Ok(5)) { Err { value = _ } => 0, Ok { value = v } => v }, 5)
      eq(sg, "match Err(3)", match (Err(3)) { Err { value = e } => e, Ok { value = _ } => 0 }, 3)
    })
  })
