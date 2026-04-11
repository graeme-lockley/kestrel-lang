import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"

fun getValue(): Int = 42
fun negate(x: Int): Int = -x

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:lang/unary", (s1: Suite) => {
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
      isFalse(sg, "!True", !True)
      isTrue(sg, "!False", !False)
      isTrue(sg, "!!True", !!True)
      isTrue(sg, "!(3>5)", !(3 > 5))
      isFalse(sg, "!(2<4)", !(2 < 4))
      isFalse(sg, "!True & False", !True & False)
      isTrue(sg, "True | !False", True | !False)
    })
  })
