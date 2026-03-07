// Runtime conformance: exception unwinding from nested calls (spec 05 §5).
// THROW must restore frame_sp and module state when unwinding to TRY handler.

// Test 1: throw from deeply nested function call
fun level3(): Int = throw(42)
fun level2(): Int = level3()
fun level1(): Int = level2()

val result1 = try {
  level1()
} catch (e) {
  e => e + 100
}
println(result1)
// 142

// Test 2: throw from nested function that uses a parameter
fun wrapper(x: Int): Int = {
  fun nested(): Int = throw(x)
  nested()
}

val result2 = try {
  wrapper(99)
} catch (e) {
  e => e + 1
}
println(result2)
// 100

// Test 3: multiple nested try/catch at different depths
fun innerThrow(): Int = throw(1)
fun middleThrow(): Int = try {
  innerThrow()
} catch (e) {
  e => throw(11)  // Re-throw with modified value
}

val result3 = try {
  middleThrow()
} catch (e) {
  e => e * 2
}
println(result3)
// 22
