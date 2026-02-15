// Lambda expression typing
fun apply(f: T -> S, x: T): S = f(x)
fun double(x: Int): Int = x * 2

val a = apply(double, 3)
val b = apply((x: Int) => x + 1, 10)
