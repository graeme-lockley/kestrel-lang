// List construction and pattern matching
val empty = []
val single = [1]
val multiple = [1, 2, 3]
val cons = 1 :: [2, 3]

fun length(xs: List<Int>): Int = match (xs) {
  [] => 0
  _ :: tail => 1
}
