// Test factorial computation with recursion
fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)

val f0 = fact(0)
val f1 = fact(1)
val f5 = fact(5)
val f7 = fact(7)
val f10 = fact(10)

println(f0)
// 1
println(f1)
// 1
println(f5)
// 120
println(f7)
// 5040
println(f10)
// 3628800

// Test with direct calls
println(fact(3))
// 6
println(fact(6))
// 720
