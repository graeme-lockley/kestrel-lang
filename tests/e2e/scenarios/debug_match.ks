// Debug match - try matching empty list
val empty = []
val result = match (empty) {
  [] => 42
  _ :: _ => 99
}
val _ = print(result)
