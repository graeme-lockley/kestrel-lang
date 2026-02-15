// Test boolean pattern matching in match expressions

fun boolToInt(b: Bool): Int = match (b) {
  True => 1
  False => 0
}

fun boolToString(b: Bool): String = match (b) {
  False => "False"
  True => "True"
}

val a = boolToInt(True)
val b = boolToInt(False)
val c = boolToString(True)
val d = boolToString(False)

println(a)
// 1
println(b)
// 0
println(c)
// True
println(d)
// False

// Match on literals
val e = match (True) {
  True => 10
  False => 20
}
val f = match (False) {
  True => 30
  False => 40
}

println(e)
// 10
println(f)
// 40
