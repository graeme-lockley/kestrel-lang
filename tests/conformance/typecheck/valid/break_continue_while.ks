// break / continue inside while; nested loop targets innermost

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

fun nestedBreakOuter(): Int = {
  var outer: Int = 0
  while (outer < 3) {
    outer := outer + 1
    var inner: Int = 0
    while (inner < 10) {
      inner := inner + 1
      if (inner == 2) {
        break
      }
    }
    if (outer == 2) {
      break
    }
  }
  outer
}

val a = sumBreakAt3()
val b = skipTwos()
val c = nestedBreakOuter()
