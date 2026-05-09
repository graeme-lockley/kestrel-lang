// Self-hosted runtime conformance: `is Int` true/false behavior.

fun isInt(x: Int | String): Bool = x is Int

println(isInt(42))
// => True

println(isInt("nope"))
// => False
