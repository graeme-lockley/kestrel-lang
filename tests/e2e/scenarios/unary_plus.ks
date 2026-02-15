// Test unary plus operator

// Basic unary plus
val a = +5
val _ = print(a)
// 5

// Unary plus on expression
val b = +(10 + 5)
val _ = print(b)
// 15

// Unary plus with unary minus
val c = +(-7)
val _ = print(c)
// -7

// Multiple unary plus
val d = +(+8)
val _ = print(d)
// 8
