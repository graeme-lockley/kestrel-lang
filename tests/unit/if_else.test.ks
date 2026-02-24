import { Suite, group, eq } from "kestrel:test"

fun classify(n: Int): Int =
  if (n < 0) 0
  else if (n == 0) 1
  else 2

export fun run(s: Suite): Unit =
  group(s, "if_else", (s1: Suite) => {
    group(s1, "branches", (sg: Suite) => {
      eq(sg, "true branch", if (True) 42 else 0, 42)
      eq(sg, "false branch", if (False) 0 else 99, 99)
    })

    group(s1, "as expression", (sg: Suite) => {
      val x = if (True) 10 else 20
      eq(sg, "bind result", x, 10)
      val y = if (False) 1 else 2
      eq(sg, "bind else result", y, 2)
    })

    group(s1, "chained", (sg: Suite) => {
      eq(sg, "classify(-5)", classify(0 - 5), 0)
      eq(sg, "classify(0)", classify(0), 1)
      eq(sg, "classify(10)", classify(10), 2)
    })

    group(s1, "nested", (sg: Suite) => {
      val a = if (True) if (False) 0 else 1 else 2
      eq(sg, "nested then branch", a, 1)
      val b = if (False) 0 else if (True) 3 else 4
      eq(sg, "nested else branch", b, 3)
    })

    group(s1, "block body", (sg: Suite) => {
      val r = if (True) { val x = 1; x + 1 } else 0
      eq(sg, "then block", r, 2)
      val r2 = if (False) 0 else { val z = 3; z * 2 }
      eq(sg, "else block", r2, 6)
    })
    
    group(s1, "comparison condition", (sg: Suite) => {
      eq(sg, "3 < 5 then", if (3 < 5) 1 else 0, 1)
      eq(sg, "5 < 3 else", if (5 < 3) 0 else 1, 1)
    })
  })
