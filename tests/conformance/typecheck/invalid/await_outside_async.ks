// EXPECT: Task
// await outside async context: async fun body must be Task<T>; top-level await would also error
async fun getTask(): Task<Int> = 1
val x = await getTask()
