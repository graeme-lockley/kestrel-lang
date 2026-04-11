#!/usr/bin/env kestrel

// Sieve of Eratosthenes — print the first `count` prime numbers, comma-separated.
import * as Arr from "kestrel:data/array"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"

// Build a composite-flag array for integers 0..limit.
// composite[i] = True means i is not prime.
fun buildSieve(limit: Int): Array<Bool> = {
  val composite = Arr.new()
  var i = 0
  while (i <= limit) {
    Arr.push(composite, False)
    i := i + 1
  }
  var p = 2
  while (p * p <= limit) {
    if (!Arr.get(composite, p)) {
      var mult = p * p
      while (mult <= limit) {
        Arr.set(composite, mult, True)
        mult := mult + p
      }
    }
    p := p + 1
  }
  composite
}

// Collect all primes from the sieve into an array.
fun collectPrimes(composite: Array<Bool>, limit: Int): Array<Int> = {
  val result = Arr.new()
  var i = 2
  while (i <= limit) {
    if (!Arr.get(composite, i)) {
      Arr.push(result, i)
    }
    i := i + 1
  }
  result
}

// Find the first `count` primes; double the sieve limit if too few are found.
fun findPrimes(count: Int, limit: Int): List<Int> = {
  val ps = collectPrimes(buildSieve(limit), limit)
  if (Arr.length(ps) >= count) Lst.take(Arr.toList(ps), count) else findPrimes(count, limit * 2)
}

// Initial limit: count * 12 is a safe overestimate of p(count) for all practical n.
fun primes(count: Int): List<Int> =
  findPrimes(count, count * 12)

println(Str.join(", ", Lst.map(primes(1000), Str.fromInt)))
