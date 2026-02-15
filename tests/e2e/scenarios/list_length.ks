// Test list length computation using recursion
fun length(xs: List<Int>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}

val empty = []
val one = [1]
val three = [1, 2, 3]
val five = [1, 2, 3, 4, 5]
val ten = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

print(length(empty))
print(length(one))
print(length(three))
print(length(five))
print(length(ten))

// Test with different values
val mixed = [42, 0, 5, 100]
print(length(mixed))
