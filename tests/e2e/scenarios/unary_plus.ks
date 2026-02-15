// Test unary plus operator

// Basic unary plus
val a = +5
val _ = println(a)
// 5

// Unary plus on expression
val b = +(10 + 5)
val _ = println(b)
// 15

// Unary plus with unary minus
val c = +(-7)
val _ = println(c)
// -7

// Multiple unary plus
val d = +(+8)
val _ = println(d)
// 8
