// Test if-else expressions with various conditions
val trueCase = if (True) 42 else 0
val falseCase = if (False) 0 else 99

println(trueCase)
// 42
println(falseCase)
// 99

// Test with comparison operators
val eq = if (5 == 5) 1 else 0
val ne = if (5 != 3) 1 else 0
val lt = if (3 < 5) 1 else 0
val gt = if (7 > 4) 1 else 0

println(eq)
// 1
println(ne)
// 1
println(lt)
// 1
println(gt)
// 1

// Test nested if-else
fun classify(n: Int): Int =
  if (n < 0) 0
  else if (n == 0) 1
  else 2

val negFive = 0 - 5
println(classify(negFive))
// 0
println(classify(0))
// 1
println(classify(10))
// 2
