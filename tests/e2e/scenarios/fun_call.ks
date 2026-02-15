// Test function calls and composition
fun double(x: Int): Int = x + x
fun triple(x: Int): Int = x * 3
fun square(x: Int): Int = x * x

val a = double(3)
val b = triple(4)
val c = square(5)

print(a)
print(b)
print(c)

// Test nested function calls
val nested = double(double(2))
val chained = triple(double(3))

print(nested)
print(chained)

// Test with zero
val zero = double(0)
print(zero)
