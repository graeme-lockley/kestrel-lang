import * as Basics from "kestrel:data/basics"
import * as Console from "kestrel:io/console"
import * as Lst from "kestrel:data/list"
import * as Stk from "kestrel:dev/stack"
import * as Str from "kestrel:data/string"
import { asyncTasksInFlight } from "kestrel:sys/task"

/** Harness output mode (`Suite.output`). Use these values only; other Int values behave like compact. */
export val outputVerbose: Int = 0
export val outputCompact: Int = 1
export val outputSummary: Int = 2

export type Suite = {
  depth: Int,
  output: Int,
  counts: {
    passed: mut Int,
    failed: mut Int,
    startTime: mut Int,
    compactExpanded: mut Bool
  }
}

/** Create a root Suite for the given output mode. Use this in generated runners instead of constructing Suite directly. */
export fun makeRoot(output: Int): Suite = {
  val counts = { mut passed = 0, mut failed = 0, mut startTime = Basics.nowMs(), mut compactExpanded = False };
  { depth = 0, output = output, counts = counts }
}

fun indent(n: Int): String = Str.concat(Lst.repeat(n, "  "))

fun groupTitleLine(s: Suite, name: String): String =
  "${indent(s.depth)}${name}"

fun passLine(s: Suite, desc: String): String =
  "${indent(s.depth)}${Console.GREEN}${Console.CHECK} ${desc}${Console.RESET}"

/** Default-weight suite name; green count + check; dim timing only. */
fun compactSummaryLine(depth: Int, name: String, passedInGroup: Int, elapsed: Int): String =
  Str.append(
    indent(depth),
    Str.append(
      name,
      Str.append(
        " (",
        Str.append(
          Console.GREEN,
          Str.append(
            Str.fromInt(passedInGroup),
            Str.append(
              Console.CHECK,
              Str.append(
                Console.RESET,
                Str.append(
                  Console.DIM,
                  Str.append(" ", Str.append(Str.fromInt(elapsed), Str.append("ms)", Console.RESET)))
                )
              )
            )
          )
        )
      )
    )
  )

fun printLinesForward(xs: List<String>): Unit = match (xs) {
  [] => (),
  h :: t => {
    println(h);
    printLinesForward(t)
  }
}

fun onAssertionPassLine(s: Suite, line: String): Unit =
  if (s.output == outputSummary) ()
  else if (s.output == outputVerbose) println(line)
  else {
    if (s.counts.compactExpanded) println(line)
    else ()
  }

fun onAssertionFailure(s: Suite): Unit = {
  s.counts.compactExpanded := True;
  ()
}

fun groupPrologue(s: Suite, name: String): Suite = {
  if (s.output == outputVerbose | (s.output == outputCompact & s.depth == 0))
    println(groupTitleLine(s, name));
  { depth = s.depth + 1, output = s.output, counts = s.counts }
}

fun groupEpilogue(s: Suite, name: String, passedStart: Int, failedStart: Int, prevExpanded: Bool, start: Int): Unit = {
  s.counts.compactExpanded := prevExpanded;
  val elapsed = Basics.nowMs() - start;
  val p = s.counts.passed - passedStart;
  val f = s.counts.failed - failedStart;

  if (s.output == outputVerbose) {
    val countStr = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
    println("${indent(s.depth)}${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}")
  } else if (s.output == outputSummary) {
    if (s.depth == 0) {
      val summaryLine = if (f > 0) {
        val countStr = "${p} passed, ${f} failed";
        "${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}"
      } else {
        compactSummaryLine(s.depth, name, p, elapsed)
      };
      println(summaryLine)
    } else ()
  } else {
    if (s.depth == 0) {
      val countStr = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
      println("${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}")
    } else {
      val summaryLine = if (f > 0) {
        val countStr = "${p} passed, ${f} failed";
        "${indent(s.depth)}${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}"
      } else {
        compactSummaryLine(s.depth, name, p, elapsed)
      };
      println(summaryLine)
    }
  }
}

export fun group(s: Suite, name: String, body: (Suite) -> Unit): Unit = {
  val start = Basics.nowMs();
  val passedStart = s.counts.passed;
  val failedStart = s.counts.failed;
  val prevExpanded = s.counts.compactExpanded;
  s.counts.compactExpanded := False;
  val child = groupPrologue(s, name);

  body(child);

  groupEpilogue(s, name, passedStart, failedStart, prevExpanded, start)
}

/** Async variant of `group`. Accepts a callback returning `Task<Unit>` so that
 *  `await` expressions can appear naturally inside group bodies.
 *  Any exception thrown by body is caught and recorded as a test failure so
 *  that sibling groups are not affected. */
export async fun asyncGroup(s: Suite, name: String, body: (Suite) -> Task<Unit>): Task<Unit> = {
  val start = Basics.nowMs();
  val passedStart = s.counts.passed;
  val failedStart = s.counts.failed;
  val prevExpanded = s.counts.compactExpanded;
  s.counts.compactExpanded := False;
  val child = groupPrologue(s, name);

  val _r = try {
    await body(child);
    True
  } catch {
    _ => {
      s.counts.failed := s.counts.failed + 1;
      s.counts.compactExpanded := True;
      println("${indent(child.depth)}${Console.RED}${Console.CROSS} group threw an unexpected exception${Console.RESET}");
      False
    }
  };

  groupEpilogue(s, name, passedStart, failedStart, prevExpanded, start)
}

/** Equality assertion using `==` (semantic / deep equality; same notion as the VM comparison for structured values). On failure, prints labelled lines so boolean, Int, Unit, String, etc. stay distinguishable via the runtime value printer. */
export fun eq(s: Suite, desc: String, actual: X, expected: X): Unit =
  if (actual == expected) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected (right): ${Stk.format(expected)}");
    println("${indent(s.depth)}  actual (left):   ${Stk.format(actual)}");
    println("${indent(s.depth)}  (deep equality / same value shape)")
  }

export fun neq(s: Suite, desc: String, actual: X, notExpected: X): Unit =
  if (actual != notExpected) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected: values must differ (deep inequality)");
    println("${indent(s.depth)}  both sides: ${Stk.format(actual)}")
  }

export fun isTrue(s: Suite, desc: String, value: Bool): Unit =
  if (value) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected (Bool): true");
    println("${indent(s.depth)}  actual (Bool):   ${Stk.format(value)}")
  }

export fun isFalse(s: Suite, desc: String, value: Bool): Unit =
  if (!value) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected (Bool): false");
    println("${indent(s.depth)}  actual (Bool):   ${Stk.format(value)}")
  }

export fun gt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left > right) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left > right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun lt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left < right) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left < right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun gte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left >= right) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  need: left >= right (total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun lte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left <= right) {
    s.counts.passed := s.counts.passed + 1;
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
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
    onAssertionPassLine(s, passLine(s, desc))
  } else {
    s.counts.failed := s.counts.failed + 1;
    onAssertionFailure(s);
    println("${indent(s.depth)}${Console.RED}${Console.CROSS} ${desc}${Console.RESET}");
    println("${indent(s.depth)}  expected: callee throws an exception");
    println("${indent(s.depth)}  actual:   completed normally (no exception)")
  }
}

export fun printSummary(root: Suite): Unit = {
  val counts = root.counts;
  val p = counts.passed;
  val f = counts.failed;
  val totalElapsed = Basics.nowMs() - counts.startTime;
  // Subtract 1 for the current (main) async task.
  val leaked = asyncTasksInFlight() - 1;
  val leakedSuffix =
    if (leaked > 0) " ${Console.YELLOW}(${leaked} async task(s) still in flight)${Console.RESET}"
    else "";
  println("");
  if (f > 0) {
    println("${Console.RED}${f} failed${Console.RESET}, ${p} passed (${totalElapsed}ms)${leakedSuffix}");
    exit(1)
  } else {
    println("${Console.GREEN}${p} passed${Console.RESET} (${totalElapsed}ms)${leakedSuffix}")
  }
}
