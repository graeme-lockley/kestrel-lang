// Test mixed unary operators

// Combination of unary operators
val a = -5 + 10
val _ = println(a)
// 5

val b = -(5 + 3) * 2
val _ = println(b)
// -16

// Unary in function
fun negate(x: Int): Int = -x
val c = negate(15)
val _ = println(c)
// -15

// Unary with boolean logic
val flag = !(3 > 5) & (2 < 4)
val _ = println(flag)
// true

// Complex expression
val result = if (!(False | False)) -100 else -200
val _ = println(result)
// -100
