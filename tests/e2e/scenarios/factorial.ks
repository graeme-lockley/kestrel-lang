// Test factorial computation with recursion
fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)

val f0 = fact(0)
val f1 = fact(1)
val f5 = fact(5)
val f7 = fact(7)
val f10 = fact(10)

print(f0)
print(f1)
print(f5)
print(f7)
print(f10)

// Test with direct calls
print(fact(3))
print(fact(6))
