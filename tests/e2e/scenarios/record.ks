// Test record creation and field access
val point = { x = 10, y = 20 }
val x1 = point.x
val y1 = point.y

print(x1)
print(y1)

// Test inline field access
val inlineX = { x = 100, y = 200 }.x
val inlineY = { x = 100, y = 200 }.y

print(inlineX)
print(inlineY)

// Test mutable fields
val box = { mut value = 0 }
print(box.value)

box.value := 42
print(box.value)

box.value := 99
print(box.value)

// Test nested records
val nested = { outer = { inner = 77 } }
val innerVal = nested.outer.inner
print(innerVal)
