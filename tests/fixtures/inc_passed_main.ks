import { incPassed } from "./inc_passed_helper.ks"

val counts = { mut passed = 0, mut failed = 0, mut startTime = 0 }
val root = { depth = 1, summaryOnly = False, counts = counts }
incPassed(root)
println(__format_one(counts.passed))
