// Row polymorphism: function parameter inferred to accept records with at least x field
fun getX(p) = p.x

val p1 = { x = 10 }
val p2 = { x = 20, y = 30 }
val p3 = { x = 5, y = 10, z = 15 }

// All three should type-check - getX accepts any record with x field
val x1 = getX(p1)
val x2 = getX(p2)
val x3 = getX(p3)
