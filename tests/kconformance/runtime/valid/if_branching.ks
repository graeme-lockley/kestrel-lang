// Self-hosted runtime conformance: if expression branch execution.
fun takeTrueArm(): String = if (True) "yes" else "no"
fun takeFalseArm(): String = if (False) "yes" else "no"
fun testNumericCond(x: Int): String = if (x > 3) "big" else "small"
fun testResultCapture(): Int = if (True) 42 else 0

fun testNoElse(): Unit = if (True) println("unit-arm")

println(takeTrueArm())
// => yes
println(takeFalseArm())
// => no
println(testNumericCond(5))
// => big
println(testNumericCond(1))
// => small
println(testResultCapture())
// => 42
testNoElse()
// => unit-arm
