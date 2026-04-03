// EXPECT: async contexts
async fun getTask(): Task<Int> = 1
async fun run(): Task<Int> = {
  fun syncHelper(x: Int): Int = await getTask()   // error: non-async block fun
  0
}
