// While loop: condition Bool, expression type Unit; body may yield a value that is discarded.
fun sumTo(n: Int): Int = {
  var i: Int = 0
  var acc: Int = 0
  while (i < n) {
    acc := acc + i
    i := i + 1
    acc
  }
  acc
}

val s = sumTo(5)
