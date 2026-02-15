// Test unary minus operator

// Basic unary minus
val a = -5
val _ = print(a)
// -5

// Unary minus on expression
val b = -(10 + 5)
val _ = print(b)
// -15

// Double negation
val c = -(-7)
val _ = print(c)
// 7

// Unary minus in arithmetic
val d = -3 * 4
val _ = print(d)
// -12

// Unary minus with function result
fun getValue(): Int = 42
val e = -getValue()
val _ = print(e)
// -42
