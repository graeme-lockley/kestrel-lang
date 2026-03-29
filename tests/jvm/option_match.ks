val x = Some(42)
val y = match (x) {
  None => 0
  Some(v) => v
}
println(y)
