// Conformance: type signature fun identity(x: T): T = x (polymorphic at multiple types)
fun identity(x: T): T = x

val a = identity(42)
val b = identity(True)
val c = identity([1, 2, 3])
