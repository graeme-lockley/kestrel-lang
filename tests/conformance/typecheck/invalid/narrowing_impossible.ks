// EXPECT: Cannot narrow
fun f(x: Int): Bool = x is String

// EXPECT: Cannot narrow
fun g(x: Int | Bool): Bool = x is String
