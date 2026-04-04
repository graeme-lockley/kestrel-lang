import { run } from "./stdlib/kestrel/http.test.ks"
import { printSummary, outputCompact } from "kestrel:test"
import { nowMs } from "kestrel:basics"

val counts = { mut passed = 0, mut failed = 0, mut startTime = nowMs(), mut compactStackBox = { frames = [] }, mut compactExpanded = False }
val root = { depth = 1, output = outputCompact, counts = counts }

async fun main(): Task<Unit> = {
  await run(root);
  printSummary(counts);
  ()
}

main()

