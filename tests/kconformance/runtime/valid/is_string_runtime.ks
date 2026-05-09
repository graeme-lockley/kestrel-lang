// Self-hosted runtime conformance: `is String` true/false behavior.

fun isString(x: Int | String): Bool = x is String

println(isString("hello"))
// => True

println(isString(42))
// => False
