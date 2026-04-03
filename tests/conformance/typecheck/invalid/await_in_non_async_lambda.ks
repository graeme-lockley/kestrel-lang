// EXPECT: async contexts
async fun getTask(): Task<Int> = 1

val badTop = (x: Int) => await getTask()

async fun run(): Task<Int> = {
  val badNested = (x: Int) => await getTask()
  0
}