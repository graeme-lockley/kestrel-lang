// Runtime conformance: ignore discards non-Unit value; println unaffected
fun double(x: Int): Int = x * 2

ignore double(3)
println(42)
// 42
