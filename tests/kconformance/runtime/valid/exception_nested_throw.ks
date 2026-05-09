// Self-hosted runtime conformance: exception unwinding through nested calls.
fun level3(): Int = throw(42)
fun level2(): Int = level3()
fun level1(): Int = level2()

val result1 = try {
  level1()
} catch (e) {
  e => e + 100
}
println(result1)
// => 142

fun wrapper(x: Int): Int = {
  fun nested(): Int = throw(x);
  nested()
}

val result2 = try {
  wrapper(99)
} catch (e) {
  e => e + 1
}
println(result2)
// => 100

fun innerThrow(): Int = throw(1)
fun middleThrow(): Int = try {
  innerThrow()
} catch (e) {
  e => throw(11)
}

val result3 = try {
  middleThrow()
} catch (e) {
  e => e * 2
}
println(result3)
// => 22
