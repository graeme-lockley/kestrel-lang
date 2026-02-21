// Option<T> — ADT with constructors Some(x), None (built-in). Type and constructors per spec 02.
export fun getOrElse(o: Option<Int>, default: Int): Int = match (o) {
  None => default
  Some{ value = x } => x
}
export fun isNone(o: Option<Int>): Bool = match (o) {
  None => True
  Some{ value = _ } => False
}
export fun isSome(o: Option<Int>): Bool = match (o) {
  None => False
  Some{ value = _ } => True
}
