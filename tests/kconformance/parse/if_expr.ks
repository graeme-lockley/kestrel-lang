// kconformance/runtime: if expressions.
val n = 5
val result = if (n > 3) "big" else "small"
println(result)
// => big
val m = 1
println(if (m == 0) "zero" else "nonzero")
// => nonzero
