import * as Basics from "kestrel:basics"
import * as Console from "kestrel:console"
import * as Lst from "kestrel:list"
import * as Stk from "kestrel:stack"
import * as Str from "kestrel:string"

/** Harness output mode (`Suite.output`). Use these values only; other Int values behave like compact. */
export val outputVerbose: Int = 0
export val outputCompact: Int = 1
export val outputSummary: Int = 2

type CompactStackBox = { frames: List<List<String>> }

export type Suite = {
  depth: Int,
  output: Int,
  counts: {
    passed: mut Int,
    failed: mut Int,
    startTime: mut Int,
    compactStackBox: mut CompactStackBox,
    compactExpanded: mut Bool
  }
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

fun flushFrameIfNonempty(lines: List<String>): Unit =
  if (Lst.length(lines) == 0) () else printLinesForward(Lst.reverse(lines))

fun printBatchesOuterFirst(frames: List<List<String>>): Unit = match (frames) {
  [] => (),
  batch :: rest => {
    flushFrameIfNonempty(batch);
    printBatchesOuterFirst(rest)
  }
}

fun emptyFrames(n: Int): List<List<String>> =
  if (n <= 0) [] else [] :: emptyFrames(n - 1)

fun flushCompactForFailure(s: Suite): Unit = match (Lst.length(s.counts.compactStackBox.frames)) {
  0 => (),
  _ => {
    val depth = Lst.length(s.counts.compactStackBox.frames);
    printBatchesOuterFirst(Lst.reverse(s.counts.compactStackBox.frames));
    s.counts.compactStackBox := { frames = emptyFrames(depth) };
    s.counts.compactExpanded := True;
    ()
  }
}

fun compactPrependToTop(s: Suite, line: String): Unit = match (s.counts.compactStackBox.frames) {
  [] => (),
  top :: rest => {
    s.counts.compactStackBox := { frames = (line :: top) :: rest };
    ()
  }
}

fun compactPop(s: Suite): List<String> = match (s.counts.compactStackBox.frames) {
  [] => [],
  h :: t => {
    s.counts.compactStackBox := { frames = t };
    h
  }
}

fun onAssertionPassLine(s: Suite, line: String): Unit =
  if (s.output == outputSummary) ()
  else {
    if (s.output == outputVerbose) println(line)
    else {
      if (s.counts.compactExpanded) println(line) else compactPrependToTop(s, line)
    }
  }

fun onAssertionFailure(s: Suite): Unit =
  if (s.output == outputCompact) flushCompactForFailure(s) else ()

export fun group(s: Suite, name: String, body: (Suite) -> Unit): Unit = {
  val start = Basics.nowMs();
  val passedStart = s.counts.passed;
  val failedStart = s.counts.failed;
  val child = { depth = s.depth + 1, output = s.output, counts = s.counts };

  if (s.output == outputVerbose) println(groupTitleLine(s, name))
  else {
    if (s.output == outputSummary) ()
    else {
      s.counts.compactExpanded := False;
      s.counts.compactStackBox := { frames = [] :: s.counts.compactStackBox.frames };
      compactPrependToTop(s, groupTitleLine(s, name))
    }
  }

  body(child);

  val elapsed = Basics.nowMs() - start;
  val p = s.counts.passed - passedStart;
  val f = s.counts.failed - failedStart;

  if (s.output == outputVerbose) {
    val countStr = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
    println("${indent(s.depth)}${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}")
  } else {
    if (s.output == outputSummary) ()
    else {
      val top = compactPop(s);
      if (f > 0) {
        flushFrameIfNonempty(top);
        val countStr = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
        println("${indent(s.depth)}${Console.DIM}${countStr} (${elapsed}ms)${Console.RESET}")
      } else {
        val summaryLine = compactSummaryLine(s.depth, name, p, elapsed);
        println(summaryLine)
      }
    }
  }
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

export fun printSummary(
  counts: {
    passed: mut Int,
    failed: mut Int,
    startTime: mut Int,
    compactStackBox: mut CompactStackBox,
    compactExpanded: mut Bool
  }
): Unit = {
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
