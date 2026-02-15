// Test record creation and field access
val point = { x = 10, y = 20 }
val x1 = point.x
val y1 = point.y

print(x1)
// 10
print(y1)
// 20

// Test inline field access
val inlineX = { x = 100, y = 200 }.x
val inlineY = { x = 100, y = 200 }.y

print(inlineX)
// 100
print(inlineY)
// 200

// Test mutable fields
val box = { mut value = 0 }
print(box.value)
// 0
box.value := 42
print(box.value)
// 42
box.value := 99
print(box.value)
// 99

// Test nested records
val nested = { outer = { inner = 77 } }
val innerVal = nested.outer.inner
print(innerVal)
// 77
