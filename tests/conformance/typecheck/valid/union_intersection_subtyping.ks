// Union parameters accept each member; return type may be a supertype of the body.
fun takeU(x: Int | Bool): Int = if (x is Int) x else 0
val a = takeU(1)
val b = takeU(True)

fun retWiden(): Int | Bool = 1

fun useInt(n: Int): Int = n
val viaUseInt = useInt(3)
