// Self-hosted runtime conformance: basic try/catch execution.
val x = try { 10 } catch (e) { e => 0 }
println(x)
// => 10

val y = try { 20 } catch (e) { e => 99 }
println(y)
// => 20
