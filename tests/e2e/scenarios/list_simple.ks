// Test list construction with cons operator and literal syntax
val empty = []
val one = 1 :: []
val two = [1, 2]
val three = [1, 2, 3]
val five = [1, 2, 3, 4, 5]

// Test list pattern matching to extract head
fun head(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => h
}

print(head(empty))
// 0
print(head(one))
// 1
print(head(two))
// 1
print(head(three))
// 1
print(head(five))
// 1

// Test that lists can be constructed and used
val list1 = [10, 20, 30]
val h1 = head(list1)
print(h1)
// 10
