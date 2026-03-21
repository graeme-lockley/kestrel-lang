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

export fun map(xs: List<A>, f: (A) -> B): List<B> = match (xs) {
  [] => []
  h :: t => f(h) :: map(t, f)
}

export fun filter(xs: List<A>, pred: (A) -> Bool): List<A> = match (xs) {
  [] => []
  h :: t => if (pred(h)) h :: filter(t, pred) else filter(t, pred)
}

export fun foldl(xs: List<A>, z: B, f: (B, A) -> B): B = match (xs) {
  [] => z
  h :: t => foldl(t, f(z, h), f)
}

fun revAppend(xs: List<T>, acc: List<T>): List<T> = match (xs) {
  [] => acc
  h :: t => revAppend(t, h :: acc)
}

export fun reverse(xs: List<T>): List<T> = revAppend(xs, [])
