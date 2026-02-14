// Exhaustive match with all constructors
val xs = [1, 2, 3]
val result = match (xs) {
  [] => 0
  head :: tail => head
}
