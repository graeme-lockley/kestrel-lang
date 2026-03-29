// Expected phase: runtime — non-tail self-recursion exceeds VM call-frame limit (8192 frames in reference VM).

fun boom(n: Int): Int =
  if (n <= 0) {
    0
  } else {
    boom(n - 1) + 1
  }

boom(10000)
