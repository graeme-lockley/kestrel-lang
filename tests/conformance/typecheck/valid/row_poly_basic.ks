// Row polymorphism: function that takes a record with x field
fun getX(p: { x: Int }): Int = p.x

val p1 = { x = 10 }
val x1 = getX(p1)
