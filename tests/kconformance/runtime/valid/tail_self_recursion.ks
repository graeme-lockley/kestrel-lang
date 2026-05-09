// Self-hosted runtime conformance: deep self-tail recursion should execute without stack overflow.

fun sumTail(n: Int, acc: Int): Int =
  if (n <= 0) acc else sumTail(n - 1, acc + n)

fun branchTail(n: Int, acc: Int): Int =
  if (n <= 0) acc
  else if (n % 2 == 0) branchTail(n - 1, acc + 1)
  else branchTail(n - 1, acc + 2)

println(sumTail(100000, 0))
// => 5000050000
println(branchTail(120000, 0))
// => 180000
