// Match using only ListPattern (no Cons pattern)
val empty = []
val result = match (empty) {
  [] => 42
}
val _ = print(result)
