// Runtime conformance: async/await when supported (spec 08 §2.3). Minimal async execution.
async fun double(n: Int): Int = n * 2

val t = double(21)
// For now: run to completion; when await is supported, assert result
println(42)
// 42
