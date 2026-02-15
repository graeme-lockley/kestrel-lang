// List<T> — Phase 5: ADT (Nil/Cons) per spec 02. Syntax [] and :: are built-in; helpers in Kestrel.
export fun length(xs: List<Int>): Int = match (xs) {
  [] => 0
  _ :: tail => 1 + length(tail)
}
export fun isEmpty(xs: List<Int>): Bool = match (xs) {
  [] => True
  _ :: _ => False
}
