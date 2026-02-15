// Test mixed unary operators

// Combination of unary operators
val a = -5 + 10
val _ = print(a)
// 5

val b = -(5 + 3) * 2
val _ = print(b)
// -16

// Unary in function
fun negate(x: Int): Int = -x
val c = negate(15)
val _ = print(c)
// -15

// Unary with boolean logic
val flag = !(3 > 5) & (2 < 4)
val _ = print(flag)
// true

// Complex expression
val result = if (!(False | False)) -100 else -200
val _ = print(result)
// -100
