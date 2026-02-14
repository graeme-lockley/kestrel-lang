// Polymorphic identity function should work with different types
fun id(x: Int): Int = x

val a = id(42)
val b = id(100)
