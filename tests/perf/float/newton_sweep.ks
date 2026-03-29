val outer = 8000
val inner = 8

fun runNewton(): Float = {
  var n = 1
  var acc = 0.0
  var a = 1.123
  while (n <= outer) {
    var x = a
    var k = 0
    while (k < inner) {
      x := 0.5 * (x + a / x)
      k := k + 1
      ()
    }
    acc := acc + x
    a := a + 1.0
    if (a > 1000.123) {
      a := 1.123
    } else {
      ()
    }
    n := n + 1
    ()
  }
  acc
}

println(runNewton())
