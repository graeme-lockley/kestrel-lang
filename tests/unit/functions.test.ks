import { Suite, group, eq } from "kestrel:test"

fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)

fun fib(n: Int): Int = if (n <= 1) n else fib(n - 1) + fib(n - 2)

fun safeDivide(a: Int, b: Int): Int = if (b == 0) 0 else a / b

fun double(x: Int): Int = x + x
fun triple(x: Int): Int = x * 3
fun square(x: Int): Int = x * x

fun increment(x: Int): Int = x + 1

fun sumList(xs: List<Int>): Int = match (xs) { [] => 0, h :: t => h + sumList(t) }

fun applyTwice(f: (Int) -> Int, x: Int): Int = f(f(x))

export fun run(s: Suite): Unit =
  group(s, "functions", (s1: Suite) => {
    group(s1, "basic calls", (sg: Suite) => {
      eq(sg, "double(3)", double(3), 6)
      eq(sg, "triple(4)", triple(4), 12)
      eq(sg, "square(5)", square(5), 25)
      eq(sg, "double(0)", double(0), 0)
      eq(sg, "increment(10)", increment(10), 11)
    })
    group(s1, "recursion", (sg: Suite) => {
      eq(sg, "safeDivide(10,2)", safeDivide(10, 2), 5)
      eq(sg, "safeDivide(10,0)", safeDivide(10, 0), 0)
      eq(sg, "safeDivide(15,3)", safeDivide(15, 3), 5)
      eq(sg, "fact(0) == 1", fact(0), 1)
      eq(sg, "fact(5) == 120", fact(5), 120)
      eq(sg, "fact(10) == 3628800", fact(10), 3628800)
      eq(sg, "fact(3)", fact(3), 6)
      eq(sg, "fib(0) == 0", fib(0), 0)
      eq(sg, "fib(1) == 1", fib(1), 1)
      eq(sg, "fib(5) == 5", fib(5), 5)
      eq(sg, "fib(10) == 55", fib(10), 55)
      eq(sg, "sumList([1,2,3])", sumList([1, 2, 3]), 6)
    })
    group(s1, "composition", (sg: Suite) => {
      eq(sg, "double(double(2))", double(double(2)), 8)
      eq(sg, "triple(double(3))", triple(double(3)), 18)
      eq(sg, "double(double(5))", double(double(5)), 20)
      eq(sg, "increment(increment(10))", increment(increment(10)), 12)
    })
    group(s1, "higher-order", (sg: Suite) => {
      eq(sg, "applyTwice lambda increment", applyTwice((x: Int) => x + 1, 0), 2)
      eq(sg, "applyTwice lambda double", applyTwice((x: Int) => x + x, 1), 4)
    })
  })
