val steps = 10000
val dx = 1.0 / 10000.0

fun runPi(): Float = {
  var i = 0
  var sum = 0.0
  var x = 0.5 * dx
  while (i < steps) {
    sum := sum + 4.0 / (1.0 + x * x)
    x := x + dx
    i := i + 1
    ()
  }
  sum * dx
}

println(runPi())
