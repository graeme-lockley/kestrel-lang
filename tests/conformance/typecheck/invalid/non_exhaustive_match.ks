// EXPECT: Non-exhaustive match
// Non-exhaustive match: missing Nil case
val xs = [1, 2, 3]
val result = match (xs) {
  Cons { head, tail } => head
}
