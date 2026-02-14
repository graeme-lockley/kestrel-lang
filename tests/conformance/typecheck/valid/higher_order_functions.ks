// Higher-order functions
fun apply(f: Int -> Int, x: Int): Int = f(x)
fun double(x: Int): Int = x * 2

val result = apply(double, 5)
