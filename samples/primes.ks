// Print the first 10,000 prime numbers, comma-separated.

import { range, filter, take, map } from "kestrel:data/list"
import { join, fromInt } from "kestrel:data/string"

fun hasDivisor(n: Int, d: Int): Bool =
  if (d * d > n) False
  else if (n % d == 0) True
  else hasDivisor(n, d + 1)

fun isPrime(n: Int): Bool =
  if (n < 2) False else !hasDivisor(n, 2)

val primes = take(filter(range(2, 120000), isPrime), 10000)
println(join(", ", map(primes, fromInt)))
