// Test nested pattern matching with lists
fun isEmpty(xs: List<Int>): Int = match (xs) {
  [] => 1
  h :: t => 0
}

val empty = []
val nonempty = [1, 2, 3]

println(isEmpty(empty))
// 1
println(isEmpty(nonempty))
// 0

// Test getting first element
fun first(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => h
}

println(first(empty))
// 0
println(first(nonempty))
// 1

// Test nested lists with matching
val list1 = [20, 30, 40]
val list2 = [5, 15, 25]

println(first(list1))
// 20
println(first(list2))
// 5

// Test matching with conditionals
fun classifyFirst(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => if (h > 10) 100 else 50
}

println(classifyFirst(empty))
// 0
println(classifyFirst(list1))
// 100
println(classifyFirst(list2))
// 50
