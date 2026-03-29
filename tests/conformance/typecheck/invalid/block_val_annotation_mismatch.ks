// EXPECT: Cannot unify
fun idInt(x: Int): Int = x
val _ = { val y: String = idInt(42); () }
