// Pattern matching with booleans
fun check(b: Bool): Int = match (b) {
  _ => 42
}

val r1 = check(True)
val r2 = check(False)

val _ = print(r1)
val _ = print(r2)
