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

println(length(empty))
// 0
println(length(one))
// 1
println(length(three))
// 3
println(length(five))
// 5
println(length(ten))
// 10

// Test with different values
val mixed = [42, 0, 5, 100]
println(length(mixed))
// 4
