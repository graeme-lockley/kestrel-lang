// Test polymorphic field access - records with different shapes
val point2d = { x = 10, y = 20 }
val point3d = { x = 5, y = 15, z = 25 }
val pointWithExtra = { x = 1, y = 2, z = 3, w = 4 }

// Direct field access works on all shapes
println(point2d.x)
// 10
println(point3d.x)
// 5
println(pointWithExtra.x)
// 1
println(point2d.y)
// 20
println(point3d.y)
// 15
println(pointWithExtra.y)
// 2

// Access fields specific to certain shapes
val z1 = point3d.z
val w1 = pointWithExtra.w

println(z1)
// 25
println(w1)
// 4

// Test with computed values
val sum2d = point2d.x + point2d.y
val sum3d = point3d.x + point3d.y + point3d.z

println(sum2d)
// 30
println(sum3d)
// 45
