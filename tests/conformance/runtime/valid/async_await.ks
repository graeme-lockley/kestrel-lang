// Runtime conformance: async function declarations compile and link (spec 08 §2.3).
// Full await/Task execution at module top level is covered by stdlib tests; this file only checks VM + codegen for async.
async fun double(n: Int): Task<Int> = n * 2

println(42)
// 42
