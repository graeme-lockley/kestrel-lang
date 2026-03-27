// EXPECT: Cannot unify types
val b = True
val result = match (b) {
  0 => 1,
  _ => 2
}
