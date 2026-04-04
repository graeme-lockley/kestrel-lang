// Runtime conformance: Task.cancel API
import { cancel, Cancelled } from "kestrel:task"
import { runProcess } from "kestrel:process"

async fun testCancelAfterComplete(): Task<Unit> = {
  async fun immediate(): Task<Int> = 42
  val t = immediate()
  val result = await t
  cancel(t)
  println(result)
}

async fun testCancelBeforeAwait(): Task<Unit> = {
  val t = runProcess("sleep", ["10"])
  cancel(t)
  try {
    await t
    println("not cancelled")
  } catch {
    Cancelled => println("caught cancelled")
  }
}

async fun run(): Task<Unit> = {
  await testCancelAfterComplete()
  await testCancelBeforeAwait()
}

run()
// 42
// caught cancelled
