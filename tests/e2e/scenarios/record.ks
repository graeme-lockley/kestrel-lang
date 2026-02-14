val r = { x = 1, y = 2 }
val a = r.x
val b = { x = 10, y = 20 }.y

val box = { mut x = 0 }
box.x := 42
val c = box.x
