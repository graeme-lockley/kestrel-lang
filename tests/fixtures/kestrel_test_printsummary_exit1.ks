// Fixture: one failing assertion then printSummary → process exits with code 1.
// Used by stdlib/kestrel/test.test.ks via kestrel:process runProcess (subprocess).
import { eq, printSummary } from "kestrel:test"

val counts = { mut passed = 0, mut failed = 0, mut startTime = __now_ms() }
val s = { depth = 0, summaryOnly = False, counts = counts }
eq(s, "intentional failure for exit-code fixture", 1, 2)
printSummary(counts)
