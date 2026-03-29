import { Suite, group, eq } from "kestrel:test"

fun boolToInt(b: Bool): Int = match (b) { True => 1, False => 0 }

fun boolToString(b: Bool): String = match (b) { False => "False", True => "True" }

fun fromOption(o: Option<Int>): Int = match (o) {
  None => 0,
  Some(x) => x
}

fun fromResult(r: Result<Int, Int>): Int = match (r) {
  Err(_) => -1,
  Ok(x) => x
}

fun sumListMatch(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => h + sumListMatch(t) }

fun makePair(): (Int * Int) = (7, 8)

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
      eq(sg, "match Some(10)", match (Some(10)) { None => 0, Some(v) => v }, 10)
      eq(sg, "match None", match (None) { None => 99, Some(_) => 0 }, 99)
    })

    group(s1, "result patterns", (sg: Suite) => {
      eq(sg, "fromResult Ok(42)", fromResult(Ok(42)), 42)
      eq(sg, "fromResult Err(1)", fromResult(Err(1)), -1)
      eq(sg, "match Ok(5)", match (Ok(5)) { Err(_) => 0, Ok(v) => v }, 5)
      eq(sg, "match Err(3)", match (Err(3)) { Err(e) => e, Ok(_) => 0 }, 3)
    })

    group(s1, "primitive literal patterns", (sg: Suite) => {
      fun classifyInt(n: Int): String = match (n) { 0 => "zero", 1 => "one", _ => "other" }
      fun classifyFloat(x: Float): Int = match (x) { 1.5 => 15, 2.0 => 20, _ => 0 }
      fun classifyString(s: String): Int = match (s) { "hello" => 1, "world" => 2, _ => 0 }
      fun classifyChar(c: Char): Int = match (c) { 'a' => 1, 'b' => 2, _ => 0 }
      fun classifyUnit(u: Unit): Int = match (u) { () => 1 }

      eq(sg, "int literal 0", classifyInt(0), "zero")
      eq(sg, "int literal fallback", classifyInt(42), "other")
      eq(sg, "float literal 1.5", classifyFloat(1.5), 15)
      eq(sg, "float literal fallback", classifyFloat(9.0), 0)
      eq(sg, "string literal hello", classifyString("hello"), 1)
      eq(sg, "string literal fallback", classifyString("z"), 0)
      eq(sg, "char literal fallback", classifyChar('z'), 0)
      eq(sg, "unit literal", classifyUnit(()), 1)
    })

    group(s1, "tuple patterns", (sg: Suite) => {
      val pair = (10, 20)
      eq(sg, "pair sum", match (pair) { (x, y) => x + y }, 30)
      eq(sg, "triple", match ((1, 2, 3)) { (a, b, c) => a + b + c }, 6)
      eq(sg, "from function", match (makePair()) { (x, y) => x + y }, 15)
      val nested = ((1, 2), 3)
      eq(sg, "nested tuple", match (nested) { ((a, b), c) => a + b + c }, 6)
      eq(sg, "wildcard slot", match ((5, 6)) { (_, y) => y }, 6)
      eq(sg, "mixed wildcards", match ((1, 2, 3)) { (_, _, z) => z }, 3)
      eq(sg, "string literal in tuple pattern", match (("hello", 2)) { ("hello", n) => n, _ => 0 }, 2)
      val mixed = (1, "x", True)
      eq(sg, "mixed types", match (mixed) { (i, s, b) => if (b) { i } else { 0 } }, 1)
      eq(sg, "literal first slot with catch-all", match ((0, 9)) { (0, y) => y, _ => 0 }, 9)
    })
  })
