// Test polymorphic field access - records with different shapes
val point2d = { x = 10, y = 20 }
val point3d = { x = 5, y = 15, z = 25 }
val pointWithExtra = { x = 1, y = 2, z = 3, w = 4 }

// Direct field access works on all shapes
print(point2d.x)
// 10
print(point3d.x)
// 5
print(pointWithExtra.x)
// 1
print(point2d.y)
// 20
print(point3d.y)
// 15
print(pointWithExtra.y)
// 2

// Access fields specific to certain shapes
val z1 = point3d.z
val w1 = pointWithExtra.w

print(z1)
// 25
print(w1)
// 4

// Test with computed values
val sum2d = point2d.x + point2d.y
val sum3d = point3d.x + point3d.y + point3d.z

print(sum2d)
// 30
print(sum3d)
// 45
