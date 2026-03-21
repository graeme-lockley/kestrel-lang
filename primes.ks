// Print the first 1000 prime numbers on a single line, comma-separated.

fun hasDivisor(n: Int, d: Int): Bool =
  if (d * d > n) {
    False
  } else if (n % d == 0) {
    True
  } else {
    hasDivisor(n, d + 1)
  }

fun isPrime(n: Int): Bool =
  if (n < 2) {
    False
  } else if (n == 2) {
    True
  } else {
    !hasDivisor(n, 2)
  }

fun printPrimes(count: Int, current: Int, printed: Int): Unit =
  if (printed >= count) {
    println("")
  } else if (isPrime(current)) {
    val _ = if (printed > 0) print(", ") else ()
    print(current)
    printPrimes(count, current + 1, printed + 1)
  } else {
    printPrimes(count, current + 1, printed)
  }

printPrimes(100, 2, 0)
