// E2E_SKIP_PENDING_CODEGEN: temporary self-hosted main stub does not execute runtime-negative scenarios; re-enable with S17-37 and dependent codegen stories
// Expected phase: runtime — non-tail self-recursion exceeds JVM call-frame limit (-Xss8m stack).

fun boom(n: Int): Int =
  if (n <= 0) {
    0
  } else {
    boom(n - 1) + 1
  }

boom(100000)
