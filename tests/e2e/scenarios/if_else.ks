// Test if-else expressions with various conditions
val trueCase = if (True) 42 else 0
val falseCase = if (False) 0 else 99

print(trueCase)
// 42
print(falseCase)
// 99

// Test with comparison operators
val eq = if (5 == 5) 1 else 0
val ne = if (5 != 3) 1 else 0
val lt = if (3 < 5) 1 else 0
val gt = if (7 > 4) 1 else 0

print(eq)
// 1
print(ne)
// 1
print(lt)
// 1
print(gt)
// 1

// Test nested if-else
fun classify(n: Int): Int =
  if (n < 0) 0
  else if (n == 0) 1
  else 2

val negFive = 0 - 5
print(classify(negFive))
// 0
print(classify(0))
// 1
print(classify(10))
// 2
