// Test row polymorphism - field access on records
val point2d = { x = 10, y = 20 }
val point3d = { x = 5, y = 15, z = 25 }

val x1 = point2d.x
val x2 = point3d.x

val _ = print(x1)
val _ = print(x2)
