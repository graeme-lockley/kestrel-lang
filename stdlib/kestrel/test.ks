import { GREEN, RED, DIM, RESET, CHECK, CROSS } from "kestrel:console"

export type Suite = { depth: Int, summaryOnly: Bool, counts: { passed: mut Int, failed: mut Int, startTime: mut Int } }

fun indent(n: Int): String =
  if (n <= 0) ""
  else "  ${indent(n - 1)}"

export fun group(s: Suite, name: String, body: (Suite) -> Unit): Unit = {
  val start = __now_ms();
  val passedStart = s.counts.passed;
  val failedStart = s.counts.failed;
  val child = { depth = s.depth + 1, summaryOnly = s.summaryOnly, counts = s.counts };

  if (!s.summaryOnly) {
    println("${indent(s.depth)}${DIM}${name}${RESET}")
  }

  body(child);

  val elapsed = __now_ms() - start;
  val p = s.counts.passed - passedStart;
  val f = s.counts.failed - failedStart;
  if (!s.summaryOnly) {
    val countStr = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
    println("${indent(s.depth)}${DIM}${countStr} (${elapsed}ms)${RESET}")
  }
}

export fun eq(s: Suite, desc: String, actual: X, expected: X): Unit =
  if (__equals(actual, expected)) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  expected: ${__format_one(expected)}");
    println("${indent(s.depth)}  actual:   ${__format_one(actual)}")
  }

export fun printSummary(counts: { passed: mut Int, failed: mut Int, startTime: mut Int }): Unit = {
  val p = counts.passed;
  val f = counts.failed;
  val totalElapsed = __now_ms() - counts.startTime;
  println("");
  if (f > 0) {
    println("${RED}${f} failed${RESET}, ${p} passed (${totalElapsed}ms)");
    exit(1)
  } else {
    println("${GREEN}${p} passed${RESET} (${totalElapsed}ms)")
  }
}
