import * as Basics from "kestrel:basics"
import * as Console from "kestrel:console"
import * as Lst from "kestrel:list"
import * as Stk from "kestrel:stack"
import * as Str from "kestrel:string"

export type Suite = { depth: Int, summaryOnly: Bool, counts: { passed: mut Int, failed: mut Int, startTime: mut Int } }

fun indent(n: Int): String = Str.concat(Lst.repeat(n, "  "))

export fun group(s: Suite, name: String, body: (Suite) -> Unit): Unit = {
  val start = Basics.nowMs();
  val passedStart = s.counts.passed;
  val failedStart = s.counts.failed;
  val child = { depth = s.depth + 1, summaryOnly = s.summaryOnly, counts = s.counts };

  if (!s.summaryOnly) {
    println("${indent(s.depth)}${Console.DIM}${name}${Console.RESET}")
  }

  body(child);

  val elapsed = Basics.nowMs() - start;
  val p = s.counts.passed - passedStart;
  val f = s.counts.failed - failedStart;
  if (!s.summaryOnly) {
    val countStr = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
    println("${indent(s.depth)}${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}")
  }
}

/** Equality assertion using `==` (semantic / deep equality; same notion as the VM comparison for structured values). On failure, prints labelled lines so boolean, Int, Unit, String, etc. stay distinguishable via the runtime value printer. */
export fun eq(s: Suite, desc: String, actual: X, expected: X): Unit =
  if (actual == expected) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected (right): ${Stk.format(expected)}");
    println("${indent(s.depth)}  actual (left):   ${Stk.format(actual)}");
    println("${indent(s.depth)}  (deep equality / same value shape)")
  }

export fun neq(s: Suite, desc: String, actual: X, notExpected: X): Unit =
  if (actual != notExpected) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected: values must differ (deep inequality)");
    println("${indent(s.depth)}  both sides: ${Stk.format(actual)}")
  }

export fun isTrue(s: Suite, desc: String, value: Bool): Unit =
  if (value) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected (Bool): true");
    println("${indent(s.depth)}  actual (Bool):   ${Stk.format(value)}")
  }

export fun isFalse(s: Suite, desc: String, value: Bool): Unit =
  if (!value) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected (Bool): false");
    println("${indent(s.depth)}  actual (Bool):   ${Stk.format(value)}")
  }

export fun gt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left > right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left > right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun lt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left < right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left < right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun gte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left >= right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left >= right (total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun lte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left <= right) {
    s.counts.passed := s.counts.passed + 1;
    if (!s.summaryOnly) {
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left <= right (total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
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
      println("${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}")
    }
  } else {
    s.counts.failed := s.counts.failed + 1;
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected: callee throws an exception");
    println("${indent(s.depth)}  actual:   completed normally (no exception)")
  }
}

export fun printSummary(counts: { passed: mut Int, failed: mut Int, startTime: mut Int }): Unit = {
  val p = counts.passed;
  val f = counts.failed;
  val totalElapsed = Basics.nowMs() - counts.startTime;
  println("");
  if (f > 0) {
    println("${Console.RED}${f} failed${Console.RESET}, ${p} passed (${totalElapsed}ms)");
    exit(1)
  } else {
    println("${Console.GREEN}${p} passed${Console.RESET} (${totalElapsed}ms)")
  }
}
