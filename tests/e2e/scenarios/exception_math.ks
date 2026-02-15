// Safe division without exceptions (uses 0 for division by zero)
fun safeDivide(a: Int, b: Int): Int = if (b == 0) 0 else a / b

val r1 = safeDivide(10, 2)
val r2 = safeDivide(10, 0)
val r3 = safeDivide(15, 3)

println(r1)
// 5
println(r2)
// 0
println(r3)
// 5
