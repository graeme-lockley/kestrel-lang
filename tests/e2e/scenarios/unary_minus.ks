// Test unary minus operator

// Basic unary minus
val a = -5
val _ = println(a)
// -5

// Unary minus on expression
val b = -(10 + 5)
val _ = println(b)
// -15

// Double negation
val c = -(-7)
val _ = println(c)
// 7

// Unary minus in arithmetic
val d = -3 * 4
val _ = println(d)
// -12

// Unary minus with function result
fun getValue(): Int = 42
val e = -getValue()
val _ = println(e)
// -42
