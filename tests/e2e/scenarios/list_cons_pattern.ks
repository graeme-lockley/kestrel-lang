// Test cons pattern in match expressions
fun length(xs: List<Int>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}

fun sum(xs: List<Int>): Int = match (xs) {
  [] => 0
  head :: tail => head + sum(tail)
}

val numbers = [1, 2, 3, 4, 5]
val len = length(numbers)
val total = sum(numbers)

print(len)
print(total)
