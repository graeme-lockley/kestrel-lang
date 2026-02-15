// Test logical not operator

val t = True
val f = False

println(!True)
// false
println(!t)
// false

println(!False)
// true
println(!f)
// true

// Double negation
println(!!True)
// true
println(!!t)
// true

// Not with comparisons
val d = !(5 > 3)
println(d)
// false
val e = !(10 == 20)
println(e)
// true

// Not in conditional
val result = if (!False) 100 else 200
println(result)
// 100
