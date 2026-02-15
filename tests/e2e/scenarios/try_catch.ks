// Placeholder test for try-catch (not fully implemented yet)
// Testing basic division and arithmetic instead

fun safeDivide(a: Int, b: Int): Int =
  if (b == 0) 0 else a / b

val result1 = safeDivide(10, 2)
val result2 = safeDivide(10, 0)
val result3 = safeDivide(20, 4)

print(result1)
// 5
print(result2)
// 0
print(result3)
// 5
