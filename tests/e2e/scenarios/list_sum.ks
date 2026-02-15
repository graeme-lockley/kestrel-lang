// Test list sum computation using recursion
fun sum(xs: List<Int>): Int = match (xs) {
  [] => 0
  head :: tail => head + sum(tail)
}

val empty = []
val list1 = [1, 2, 3, 4, 5]
val list2 = [10, 20, 30]
val list3 = [100]
val list4 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

print(sum(empty))
print(sum(list1))
print(sum(list2))
print(sum(list3))
print(sum(list4))

// Test with mixed values
val withZero = [10, 0, 3]
print(sum(withZero))
