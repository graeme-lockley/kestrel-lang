// Test function calls and composition
fun double(x: Int): Int = x + x
fun triple(x: Int): Int = x * 3
fun square(x: Int): Int = x * x

val a = double(3)
val b = triple(4)
val c = square(5)

println(a)
// 6
println(b)
// 12
println(c)
// 25

// Test nested function calls
val nested = double(double(2))
val chained = triple(double(3))

println(nested)
// 8
println(chained)
// 18

// Test with zero
val zero = double(0)
println(zero)
// 0
