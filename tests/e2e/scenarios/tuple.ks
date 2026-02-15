// Test tuple creation and element access
val pair = (10, 20)
println(pair.0)
// 10
println(pair.1)
// 20

// Test inline tuple access
val first = (100, 200, 300).0
val second = (100, 200, 300).1
val third = (100, 200, 300).2

println(first)
// 100
println(second)
// 200
println(third)
// 300

// Test nested tuples
val nested = ((1, 2), (3, 4))
val a = nested.0.0
val b = nested.0.1
val c = nested.1.0
val d = nested.1.1

println(a)
// 1
println(b)
// 2
println(c)
// 3
println(d)
// 4
