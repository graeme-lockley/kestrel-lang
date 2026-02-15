// Test unary minus operator

// Basic unary minus
val a = -5
val _ = print(a)

// Unary minus on expression
val b = -(10 + 5)
val _ = print(b)

// Double negation
val c = -(-7)
val _ = print(c)

// Unary minus in arithmetic
val d = -3 * 4
val _ = print(d)

// Unary minus with function result
fun getValue(): Int = 42
val e = -getValue()
val _ = print(e)
