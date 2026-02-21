// List<T> — ADT with Nil, Cons(head, tail). Syntax [], [a,b,...c], :: built-in. Type and constructors per spec 02.
export fun length(xs: List<Int>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}
export fun isEmpty(xs: List<Int>): Bool = match (xs) {
  [] => True
  _ :: _ => False
}
