// Self-hosted runtime conformance: mutual recursion remains semantically correct.
// This story does not implement mutual-TCO; this test guards behavior only.

fun isEven(n: Int): Bool =
  if (n == 0) True else isOdd(n - 1)

fun isOdd(n: Int): Bool =
  if (n == 0) False else isEven(n - 1)

println(isEven(42))
// => True
println(isOdd(99))
// => True
