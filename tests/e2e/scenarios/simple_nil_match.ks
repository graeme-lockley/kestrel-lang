// Simple Nil match test
fun isNil(xs: List<Int>): Int = match (xs) {
  [] => 1
  _ :: _ => 0
}

val empty = []
val result = isNil(empty)
val _ = print(result)
