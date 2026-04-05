import * as Task from "kestrel:sys/task"

async fun mkInt(x: Int): Task<Int> = x

async fun run(): Task<Unit> = {
  val doubled = Task.map(mkInt(21), (x: Int) => x * 2)
  println(await doubled)

  val results = await Task.all([mkInt(10), mkInt(20), mkInt(30)])
  println(results)

  val winner = await Task.race([mkInt(42)])
  println(winner)
}

run()
// 42
// [10, 20, 30]
// 42
