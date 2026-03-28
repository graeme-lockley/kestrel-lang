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

/** Equality assertion using deep structural equality (`__equals`). On failure, prints labelled lines so boolean, Int, Unit, String, etc. stay distinguishable via the runtime value printer. */
export fun eq(s: Suite, desc: String, actual: X, expected: X): Unit =
  if (__equals(actual, expected)) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  expected (right): ${__format_one(expected)}");
    println("${indent(s.depth)}  actual (left):   ${__format_one(actual)}");
    println("${indent(s.depth)}  (deep equality / same value shape)")
  }

export fun neq(s: Suite, desc: String, actual: X, notExpected: X): Unit =
  if (!__equals(actual, notExpected)) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  expected: values must differ (deep inequality)");
    println("${indent(s.depth)}  both sides: ${__format_one(actual)}")
  }

export fun isTrue(s: Suite, desc: String, value: Bool): Unit =
  if (value) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  expected (Bool): true");
    println("${indent(s.depth)}  actual (Bool):   ${__format_one(value)}")
  }

export fun isFalse(s: Suite, desc: String, value: Bool): Unit =
  if (!value) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  expected (Bool): false");
    println("${indent(s.depth)}  actual (Bool):   ${__format_one(value)}")
  }

export fun gt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left > right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  need: left > right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${__format_one(left)}");
    println("${indent(s.depth)}  right (Int): ${__format_one(right)}")
  }

export fun lt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left < right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  need: left < right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${__format_one(left)}");
    println("${indent(s.depth)}  right (Int): ${__format_one(right)}")
  }

export fun gte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left >= right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  need: left >= right (total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${__format_one(left)}");
    println("${indent(s.depth)}  right (Int): ${__format_one(right)}")
  }

export fun lte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left <= right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  need: left <= right (total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${__format_one(left)}");
    println("${indent(s.depth)}  right (Int): ${__format_one(right)}")
  }

/**
 * Assert that `thunk` throws when invoked with unit `()`.
 * Kestrel does not parse `() -> Unit` in type position; the thunk therefore takes `Unit` so callers pass e.g. `(_: Unit) => { ... }` and the harness calls `thunk(())`.
 */
export fun throws(s: Suite, desc: String, thunk: (Unit) -> Unit): Unit = {
  val threw =
    try {
      thunk(());
      False
    } catch {
      _ => True
    };
  if (threw) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${GREEN}${CHECK} ${desc}${RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${RED}${CROSS} ${desc}${RESET}");
    println("${indent(s.depth)}  expected: callee throws an exception");
    println("${indent(s.depth)}  actual:   completed normally (no exception)")
  }
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
