import { Suite, group, eq } from "kestrel:test"

fun sumTo(n: Int): Int = {
  var i: Int = 0
  var acc: Int = 0

  while (i < n) {
    acc := acc + i
    i := i + 1
  }
  
  acc
}

fun countWithWhile(limit: Int): Int = {
  var c: Int = 0
  
  while (c < limit) {
    c := c + 1
  }

  c
}

export fun run(s: Suite): Unit =
  group(s, "while", (s1: Suite) => {
    group(s1, "sum", (sg: Suite) => {
      eq(sg, "sumTo(0)", sumTo(0), 0)
      eq(sg, "sumTo(5)", sumTo(5), 10)
    })
    group(s1, "iteration_count", (sg: Suite) => {
      eq(sg, "zero iterations", countWithWhile(0), 0)
      eq(sg, "many iterations", countWithWhile(5000), 5000)
    })
  })
