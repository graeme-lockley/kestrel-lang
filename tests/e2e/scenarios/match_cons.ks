// Test matching non-empty list
val nums = [5]
val result = match (nums) {
  [] => 0
  _ :: _ => 99
}
val _ = print(result)
