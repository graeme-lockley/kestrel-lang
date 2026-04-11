import { outputCompact } from "kestrel:dev/test"
import { incPassed } from "./inc_passed_helper.ks"

val counts = {
  mut passed = 0,
  mut failed = 0,
  mut startTime = 0,
  mut compactStackBox = { frames = [] },
  mut compactExpanded = False
}
val root = { depth = 1, output = outputCompact, counts = counts }
incPassed(root)
println(__format_one(counts.passed))
