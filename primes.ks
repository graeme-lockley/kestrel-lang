// Print the first 10,000 prime numbers on a single line, comma-separated.
// Iterative (while) only — no recursion so the stack stays bounded.

fun hasDivisor(n: Int): Bool = {
  var d = 2

  while (d * d <= n) {
    if (n % d == 0) {
      break
    }

    d := d + 1
  }

  d * d <= n
}

fun isPrime(n: Int): Bool =
  if (n < 2)
    False
  else if (n == 2)
    True
  else
    !hasDivisor(n)

fun printPrimes(count: Int): Unit = {
  var current = 2
  var printed = 0

  while (printed < count) {
    if (isPrime(current)) {
      if (printed > 0) 
        print(", ")
      print(current)

      printed := printed + 1
    }
    current := current + 1
  }

  println("")
}

printPrimes(10000)
