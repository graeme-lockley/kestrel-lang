// Expected phase: runtime — non-tail self-recursion exceeds JVM call-frame limit (-Xss8m stack).

fun boom(n: Int): Int =
  if (n <= 0) {
    0
  } else {
    boom(n - 1) + 1
  }

boom(100000)
