// Test if case body executes
val empty = []
val result = match (empty) {
  [] => 42 + 0
}
val _ = print(result)
