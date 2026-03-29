// EXPECT: Cannot unify
fun f(x: Int): String = g(x)
fun g(x: Int): Int = f(x)
