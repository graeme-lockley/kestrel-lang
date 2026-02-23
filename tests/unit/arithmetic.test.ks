import { Suite, group, eq } from "kestrel:test"

fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)

fun fib(n: Int): Int = if (n <= 1) n else fib(n - 1) + fib(n - 2)

fun safeDivide(a: Int, b: Int): Int = if (b == 0) 0 else a / b

fun double(x: Int): Int = x + x
fun triple(x: Int): Int = x * 3
fun square(x: Int): Int = x * x

fun getValue(): Int = 42
fun negate(x: Int): Int = 0 - x

export fun run(s: Suite): Unit =
  group(s, "arithmetic", (s1: Suite) => {
    eq(s1, "2 + 3 == 5", "${2 + 3}", "${5}");
    eq(s1, "10 - 4 == 6", "${10 - 4}", "${6}");
    eq(s1, "3 * 7 == 21", "${3 * 7}", "${21}");
    eq(s1, "20 / 4 == 5", "${20 / 4}", "${5}");
    eq(s1, "17 % 5 == 2", "${17 % 5}", "${2}");
    eq(s1, "2 ** 10 == 1024", "${2 ** 10}", "${1024}");

    group(s1, "safeDivide", (sd: Suite) => {
      eq(sd, "safeDivide(10,2)", "${safeDivide(10, 2)}", "${5}");
      eq(sd, "safeDivide(10,0)", "${safeDivide(10, 0)}", "${0}");
      eq(sd, "safeDivide(15,3)", "${safeDivide(15, 3)}", "${5}");
      ()
    });

    group(s1, "precedence and chain", (pc: Suite) => {
      eq(pc, "2+3*4", "${2 + 3 * 4}", "${14}");
      eq(pc, "(2+3)*4", "${(2 + 3) * 4}", "${20}");
      eq(pc, "100/10/2", "${100 / 10 / 2}", "${5}");
      eq(pc, "10-3-2", "${10 - 3 - 2}", "${5}");
      eq(pc, "10+5", "${10 + 5}", "${15}");
      eq(pc, "6*7", "${6 * 7}", "${42}");
      eq(pc, "20/4", "${20 / 4}", "${5}");
      eq(pc, "17%5", "${17 % 5}", "${2}");
      ()
    });

    group(s1, "fun_call", (fc: Suite) => {
      eq(fc, "double(3)", "${double(3)}", "${6}");
      eq(fc, "triple(4)", "${triple(4)}", "${12}");
      eq(fc, "square(5)", "${square(5)}", "${25}");
      eq(fc, "double(double(2))", "${double(double(2))}", "${8}");
      eq(fc, "triple(double(3))", "${triple(double(3))}", "${18}");
      eq(fc, "double(0)", "${double(0)}", "${0}");
      ()
    });

    group(s1, "unary", (un: Suite) => {
      eq(un, "+5", "${+5}", "${5}");
      eq(un, "+(10+5)", "${+(10 + 5)}", "${15}");
      eq(un, "+(-7)", "${+(0 - 7)}", "${-7}");
      eq(un, "-5", "${0 - 5}", "${-5}");
      eq(un, "-(10+5)", "${0 - (10 + 5)}", "${-15}");
      eq(un, "-(-7)", "${0 - (0 - 7)}", "${7}");
      eq(un, "-3*4", "${0 - 3 * 4}", "${-12}");
      eq(un, "-getValue()", "${0 - getValue()}", "${-42}");
      eq(un, "-5+10", "${0 - 5 + 10}", "${5}");
      eq(un, "-(5+3)*2", "${(0 - (5 + 3)) * 2}", "${-16}");
      eq(un, "negate(15)", "${negate(15)}", "${-15}");
      ()
    });

    group(s1, "factorial", (fac: Suite) => {
      eq(fac, "fact(0) == 1", "${fact(0)}", "${1}");
      eq(fac, "fact(5) == 120", "${fact(5)}", "${120}");
      eq(fac, "fact(10) == 3628800", "${fact(10)}", "${3628800}");
      eq(fac, "fact(3)", "${fact(3)}", "${6}");
      eq(fac, "fact(6)", "${fact(6)}", "${720}");
      ()
    });

    group(s1, "fibonacci", (fi: Suite) => {
      eq(fi, "fib(0) == 0", "${fib(0)}", "${0}");
      eq(fi, "fib(1) == 1", "${fib(1)}", "${1}");
      eq(fi, "fib(5) == 5", "${fib(5)}", "${5}");
      eq(fi, "fib(10) == 55", "${fib(10)}", "${55}");
      ()
    });
    ()
  })
