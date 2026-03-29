val steps = 25000

fun runHarmonic(): Float = {
  var i = 1
  var x = 1.0
  var sum = 0.0
  while (i <= steps) {
    sum := sum + 1.0 / x
    x := x + 1.0
    i := i + 1
    ()
  }
  sum
}

println(runHarmonic())
