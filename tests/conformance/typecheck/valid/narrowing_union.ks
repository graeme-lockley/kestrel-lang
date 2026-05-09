fun f(x: Int | Bool): Int = if (x is Int) { x + 1 } else { 0 }

fun g(x0: Int | Bool): Int = {
  var x = x0
  var out = 0
  while (x is Int) {
    out := x + 1
    break
  }
  out
}

val a = f(1)
val b = f(True)
val c = g(3)
val d = g(False)
