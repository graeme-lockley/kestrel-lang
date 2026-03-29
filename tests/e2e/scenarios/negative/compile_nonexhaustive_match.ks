// Expected phase: compile — non-exhaustive `match` on list (missing Nil).

val xs = [1, 2, 3]
val result = match (xs) {
  Cons { head, tail } => head
}
