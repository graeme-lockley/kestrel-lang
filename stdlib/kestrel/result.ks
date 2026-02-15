// Result<T, E> — Phase 5: ADT (Ok/Err) per spec 02. Constructors are built-in; helpers in Kestrel.
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
