// Composition: applying functions in sequence
fun double(x: Int): Int = x * 2
fun increment(x: Int): Int = x + 1

// Manual function composition
val a = double(double(5))
val b = increment(increment(10))

print(a)
// 20
print(b)
// 12
