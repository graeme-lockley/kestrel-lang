import { Suite, group, eq, isTrue } from "kestrel:tools/test"
import { map, all, race, cancel, Cancelled } from "kestrel:sys/task"
import { runProcess } from "kestrel:sys/process"

async fun mkInt(x: Int): Task<Int> = x

export async fun run(s: Suite): Task<Unit> = {
  val mapDouble  = await map(mkInt(21), (x: Int) => x * 2)
  val mapAdd     = await map(mkInt(10), (x: Int) => x + 5)
  val mapToBool  = await map(mkInt(5), (x: Int) => x == 5)

  val allThree  = await all([mkInt(1), mkInt(2), mkInt(3)])
  val allSingle = await all([mkInt(99)])

  val raceOne = await race([mkInt(42)])

  val completedTask = mkInt(5)
  val completedVal  = await completedTask
  cancel(completedTask)

  val slowTask = runProcess("sleep", ["10"])
  cancel(slowTask)
  val cancelCaught: Int =
    try {
      await slowTask
      0
    } catch {
      Cancelled => 1
    }

  group(s, "task", (s1: Suite) => {
    group(s1, "map", (sg: Suite) => {
      eq(sg, "map double", mapDouble, 42)
      eq(sg, "map add", mapAdd, 15)
      isTrue(sg, "map to different type", mapToBool)
    });

    group(s1, "all", (sg: Suite) => {
      eq(sg, "all preserves order", allThree, [1, 2, 3])
      eq(sg, "all single element", allSingle, [99])
    });

    group(s1, "race", (sg: Suite) => {
      eq(sg, "race single task", raceOne, 42)
    });

    group(s1, "cancel", (sg: Suite) => {
      eq(sg, "cancel after complete is no-op", completedVal, 5)
      eq(sg, "cancel before await catches Cancelled", cancelCaught, 1)
    });
  });
  ()
}
