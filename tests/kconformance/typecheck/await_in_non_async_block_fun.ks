// Provenance: tests/conformance/typecheck/invalid/await_in_non_async_block_fun.ks (baseline S17-50)
// EXPECT: async contexts
async fun getTask(): Task<Int> = 1
async fun run(): Task<Int> = {
  fun syncHelper(x: Int): Int = await getTask()   // error: non-async block fun
  0
}
