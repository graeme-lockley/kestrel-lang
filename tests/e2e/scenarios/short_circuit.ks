// Test short-circuit boolean operators
val andTT = True & True
val andTF = True & False
val andFT = False & True
val andFF = False & False

val orTT = True | True
val orTF = True | False
val orFT = False | True
val orFF = False | False

// Convert booleans to integers for printing
fun boolToInt(b: Bool): Int = if (b) 1 else 0

println(boolToInt(andTT))
// 1
println(boolToInt(andTF))
// 0
println(boolToInt(andFT))
// 0
println(boolToInt(andFF))
// 0
println(boolToInt(orTT))
// 1
println(boolToInt(orTF))
// 1
println(boolToInt(orFT))
// 1
println(boolToInt(orFF))
// 0

// Test with complex expressions
val complex1 = (5 > 3) & (10 < 20)
val complex2 = (5 > 10) | (3 == 3)

println(boolToInt(complex1))
// 1
println(boolToInt(complex2))
// 1
