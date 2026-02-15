// Test polymorphic field access - records with different shapes
val point2d = { x = 10, y = 20 }
val point3d = { x = 5, y = 15, z = 25 }
val pointWithExtra = { x = 1, y = 2, z = 3, w = 4 }

// Direct field access works on all shapes
print(point2d.x)
print(point3d.x)
print(pointWithExtra.x)

print(point2d.y)
print(point3d.y)
print(pointWithExtra.y)

// Access fields specific to certain shapes
val z1 = point3d.z
val w1 = pointWithExtra.w

print(z1)
print(w1)

// Test with computed values
val sum2d = point2d.x + point2d.y
val sum3d = point3d.x + point3d.y + point3d.z

print(sum2d)
print(sum3d)
