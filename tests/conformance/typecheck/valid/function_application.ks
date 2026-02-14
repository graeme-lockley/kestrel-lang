// Function application and type inference
fun double(x: Int): Int = x * 2
fun add(a: Int, b: Int): Int = a + b

val a = double(5)
val b = add(1, 2)
val c = add(double(3), 4)
