// Test factorial computation with recursion
fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)

val f0 = fact(0)
val f1 = fact(1)
val f5 = fact(5)
val f7 = fact(7)
val f10 = fact(10)

print(f0)
// 1
print(f1)
// 1
print(f5)
// 120
print(f7)
// 5040
print(f10)
// 3628800

// Test with direct calls
print(fact(3))
// 6
print(fact(6))
// 720
