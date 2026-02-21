// Result<T, E> — ADT with constructors Ok(x), Err(e) (built-in). Type and constructors per spec 02.
export fun getOrElse(r: Result<Int, Int>, default: Int): Int = match (r) {
  Err{ value = _ } => default
  Ok{ value = x } => x
}
export fun isOk(r: Result<Int, Int>): Bool = match (r) {
  Err{ value = _ } => False
  Ok{ value = _ } => True
}
export fun isErr(r: Result<Int, Int>): Bool = match (r) {
  Err{ value = _ } => True
  Ok{ value = _ } => False
}
