// List<T> — ADT with Nil, Cons(head, tail). Syntax [], [a,b,...c], :: built-in. Type and constructors per spec 02.

export fun length(xs: List<X>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}

export fun isEmpty(xs: List<X>): Bool = match (xs) {
  [] => True
  _ => False
}

export fun drop(n: Int, xs: List<T>): List<T> =
  if (n <= 0) xs
  else match (xs) {
    [] => [],
    _ :: tl => drop(n - 1, tl)
  }
