import { Suite, group, eq } from "kestrel:dev/test"

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

fun sumBreakAt3(): Int = {
  var i: Int = 0
  var acc: Int = 0
  while (i < 10) {
    i := i + 1
    if (i > 3) {
      break
    }
    acc := acc + i
  }
  acc
}

fun skipTwos(): Int = {
  var i: Int = 0
  var acc: Int = 0
  while (i < 5) {
    i := i + 1
    if (i == 2) {
      continue
    }
    acc := acc + i
  }
  acc
}

fun nestedTargetsInnerWhile(): Int = {
  var total: Int = 0
  var o: Int = 0
  while (o < 2) {
    o := o + 1
    var inner: Int = 0
    while (inner < 5) {
      inner := inner + 1
      if (inner == 3) {
        break
      }
      total := total + 1
    }
  }
  total
}

export async fun run(s: Suite): Task<Unit> =
  group(s, "while", (s1: Suite) => {
    group(s1, "sum", (sg: Suite) => {
      eq(sg, "sumTo(0)", sumTo(0), 0)
      eq(sg, "sumTo(5)", sumTo(5), 10)
    })
    group(s1, "iteration_count", (sg: Suite) => {
      eq(sg, "zero iterations", countWithWhile(0), 0)
      eq(sg, "many iterations", countWithWhile(5000), 5000)
    })
    group(s1, "break_continue", (sg: Suite) => {
      eq(sg, "break stops loop", sumBreakAt3(), 6)
      eq(sg, "continue skips iteration", skipTwos(), 13)
      eq(sg, "nested break inner loop", nestedTargetsInnerWhile(), 4)
    })
  })
