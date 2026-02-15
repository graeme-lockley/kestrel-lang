// Test nested pattern matching with lists
fun isEmpty(xs: List<Int>): Int = match (xs) {
  [] => 1
  h :: t => 0
}

val empty = []
val nonempty = [1, 2, 3]

print(isEmpty(empty))
// 1
print(isEmpty(nonempty))
// 0

// Test getting first element
fun first(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => h
}

print(first(empty))
// 0
print(first(nonempty))
// 1

// Test nested lists with matching
val list1 = [20, 30, 40]
val list2 = [5, 15, 25]

print(first(list1))
// 20
print(first(list2))
// 5

// Test matching with conditionals
fun classifyFirst(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => if (h > 10) 100 else 50
}

print(classifyFirst(empty))
// 0
print(classifyFirst(list1))
// 100
print(classifyFirst(list2))
// 50
