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

print(a)
// 1
print(b)
// 0
print(c)
// True
print(d)
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

print(e)
// 10
print(f)
// 40
