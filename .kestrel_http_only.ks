import { printSummary, outputVerbose } from "kestrel:test"
import { nowMs } from "kestrel:basics"
import { run as run0 } from "/Users/graemelockley/Projects/kestrel/stdlib/kestrel/http.test.ks"

val counts = { mut passed = 0, mut failed = 0, mut startTime = nowMs(), mut compactStackBox = { frames = [] }, mut compactExpanded = False }
val root = { depth = 1, output = outputVerbose, counts = counts }

async fun main(): Task<Unit> = {
  await run0(root)
  printSummary(counts);
  ()
}

main()
