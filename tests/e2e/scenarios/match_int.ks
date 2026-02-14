// Test match on integer (non-ADT)
val x = 5
val result = match (x) {
  _ => 42
}
val _ = print(result)
