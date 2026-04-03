// compile error: await outside async context
async fun getTask(): Task<Int> = 1
val x = await getTask()
