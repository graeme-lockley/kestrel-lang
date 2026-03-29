val steps = 50000

fun runLogistic(): Float = {
  var i = 0
  var x = 0.499999
  var acc = 0.0
  while (i < steps) {
    x := 3.99991 * x * (1.0 - x)
    acc := acc + x
    i := i + 1
    ()
  }
  acc
}

println(runLogistic())
