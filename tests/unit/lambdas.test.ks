import { Suite, group, eq } from "kestrel:test"

fun apply(f: (Int) -> Int, x: Int): Int = f(x)

fun applyTwice(f: (Int) -> Int, x: Int): Int = f(f(x))

export fun run(s: Suite): Unit =
  group(s, "lambdas", (s1: Suite) => {
    group(s1, "basic", (sg: Suite) => {
      eq(sg, "(x) => x + 1 applied to 5", ((x: Int) => x + 1)(5), 6)
      eq(sg, "(x) => x * 2 applied to 7", ((x: Int) => x * 2)(7), 14)
      eq(sg, "two-arg lambda", ((a: Int, b: Int) => a + b)(10, 20), 30)
    })

    group(s1, "closures", (sg: Suite) => {
      val base = 100
      eq(sg, "capture val", ((x: Int) => base + x)(5), 105)

      val prefix = "hello "
      eq(sg, "capture string", ((s: String) => "${prefix}${s}")("world"), "hello world")
    })

    group(s1, "as argument", (sg: Suite) => {
      eq(sg, "lambda to apply", apply((x: Int) => x + 10, 2), 12)
      eq(sg, "lambda to applyTwice", applyTwice((x: Int) => x * 2, 3), 12)
    })

    group(s1, "indirect call", (sg: Suite) => {
      val addOne = (x: Int) => x + 1
      eq(sg, "call through val", addOne(41), 42)

      val mul = (a: Int, b: Int) => a * b
      eq(sg, "two-arg through val", mul(6, 7), 42)
    })

    group(s1, "generic lambdas", (sg: Suite) => {
      val genId = <T>(x: T) => x
      eq(sg, "identity Int", genId(42), 42)
      eq(sg, "identity String", genId("hello"), "hello")

      val genSwap = <T, U>(a: T, b: U) => (b, a)
      eq(sg, "swap types", genSwap(1, "a"), ("a", 1))

      val genFirst = <T, U>(p: (T, U)) => match (p) { (x, y) => x }
      eq(sg, "first of pair", genFirst((10, "x")), 10)
    })
  })
