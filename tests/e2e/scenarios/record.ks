// Test record creation and field access
val point = { x = 10, y = 20 }
val x1 = point.x
val y1 = point.y

println(x1)
// 10
println(y1)
// 20

// Test inline field access
val inlineX = { x = 100, y = 200 }.x
val inlineY = { x = 100, y = 200 }.y

println(inlineX)
// 100
println(inlineY)
// 200

// Test mutable fields
val box = { mut value = 0 }
println(box.value)
// 0
box.value := 42
println(box.value)
// 42
box.value := 99
println(box.value)
// 99

// Test nested records
val nested = { outer = { inner = 77 } }
val innerVal = nested.outer.inner
println(innerVal)
// 77
