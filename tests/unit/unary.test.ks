import { Suite, group, eq } from "kestrel:test"

fun getValue(): Int = 42
fun negate(x: Int): Int = -x

export fun run(s: Suite): Unit =
  group(s, "unary", (s1: Suite) => {
    group(s1, "plus", (sg: Suite) => {
      eq(sg, "+5", +5, 5)
      eq(sg, "+(10+5)", +(10 + 5), 15)
      eq(sg, "+(-7)", +(-7), -7)
    })

    group(s1, "minus", (sg: Suite) => {
      eq(sg, "-5", -5, -5)
      eq(sg, "-(10+5)", -(10 + 5), -15)
      eq(sg, "-(-7)", -(-7), 7)
      eq(sg, "-3*4", -3 * 4, -12)
      eq(sg, "-getValue()", -getValue(), -42)
      eq(sg, "-5+10", -5 + 10, 5)
      eq(sg, "-(5+3)*2", -(5 + 3) * 2, -16)
      eq(sg, "negate(15)", negate(15), -15)
    })
    
    group(s1, "not", (sg: Suite) => {
      eq(sg, "!True", !True, False)
      eq(sg, "!False", !False, True)
      eq(sg, "!!True", !!True, True)
      eq(sg, "!(3>5)", !(3 > 5), True)
      eq(sg, "!(2<4)", !(2 < 4), False)
      eq(sg, "!True & False", !True & False, False)
      eq(sg, "True | !False", True | !False, True)
    })
  })
