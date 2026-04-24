//! Lightweight test harness used by stdlib and project tests.
//!
//! Provides grouped assertions, summary/verbose output modes, and utility checks.
//! Integrates with [`kestrel:io/console`](/docs/kestrel:io/console) for terminal
//! output and [`kestrel:dev/stack`](/docs/kestrel:dev/stack) for value formatting.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import { Suite, group, eq, isTrue } from "kestrel:dev/test"
//!
//! export async fun run(s: Suite): Task<Unit> =
//!   group(s, "math", (g: Suite) => {
//!     eq(g, "2+2", 2 + 2, 4)
//!     isTrue(g, "positive", 4 > 0)
//!   })
//! ```

import * as Basics from "kestrel:data/basics"
import * as Console from "kestrel:io/console"
import * as Lst from "kestrel:data/list"
import * as Stk from "kestrel:dev/stack"
import * as Str from "kestrel:data/string"
import { asyncTasksInFlight } from "kestrel:sys/task"

val _isTty = Console.terminalInfo().isTty
val _grn = if (_isTty) Console.GREEN else ""
val _red = if (_isTty) Console.RED else ""
val _yel = if (_isTty) Console.YELLOW else ""
val _dim = if (_isTty) Console.DIM else ""
val _rst = if (_isTty) Console.RESET else ""
val _asyncInFlightBaseline = asyncTasksInFlight()

// ─── Harness types and output modes ──────────────────────────────────────────

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

// ─── Internal formatting helpers ─────────────────────────────────────────────

fun indent(n: Int): String = Str.concat(Lst.repeat(n, "  "))

fun passLine(s: Suite, desc: String): String =
  "${indent(s.depth)}${_grn}${Console.CHECK} ${desc}${_rst}"

/** Default-weight suite name; green count + check; dim timing only. */
fun compactSummaryLine(depth: Int, name: String, passedInGroup: Int, elapsed: Int): String =
  "${indent(depth)}${name} (${_grn}${passedInGroup}${Console.CHECK}${_rst}${_dim} ${elapsed}ms)${_rst}"

fun countFooter(p: Int, f: Int, elapsed: Int): String = {
  val counts = if (f > 0) "${p} passed, ${f} failed" else "${p} passed";
  "${_dim}${counts} (${elapsed}ms)${_rst}"
}

// ─── Assertion bookkeeping ────────────────────────────────────────────────────

fun recordPass(s: Suite, desc: String): Unit = {
  s.counts.passed := s.counts.passed + 1;
  if (s.output == outputVerbose | (s.output == outputCompact & s.counts.compactExpanded))
    println(passLine(s, desc))
  else ()
}

fun recordFail(s: Suite, desc: String): Unit = {
  s.counts.failed := s.counts.failed + 1;
  s.counts.compactExpanded := True;
  println("${indent(s.depth)}${_red}${Console.CROSS} ${desc}${_rst}")
}

// ─── Group prologue / epilogue ────────────────────────────────────────────────

fun groupPrologue(s: Suite, name: String): Suite = {
  if (s.output == outputVerbose | (s.output == outputCompact & s.depth == 0))
    println("${indent(s.depth)}${name}");
  { depth = s.depth + 1, output = s.output, counts = s.counts }
}

fun groupEpilogue(s: Suite, name: String, passedStart: Int, failedStart: Int, prevExpanded: Bool, start: Int): Unit = {
  s.counts.compactExpanded := prevExpanded;
  val elapsed = Basics.nowMs() - start;
  val p = s.counts.passed - passedStart;
  val f = s.counts.failed - failedStart;

  if (s.output == outputVerbose)
    println("${indent(s.depth)}${countFooter(p, f, elapsed)}")
  else if (s.output == outputSummary) {
    if (s.depth == 0) {
      val line = if (f > 0) countFooter(p, f, elapsed) else compactSummaryLine(0, name, p, elapsed);
      println(line)
    } else ()
  } else {
    // compact mode
    if (s.depth == 0)
      println(countFooter(p, f, elapsed))
    else {
      val line = if (f > 0) "${indent(s.depth)}${countFooter(p, f, elapsed)}" else compactSummaryLine(s.depth, name, p, elapsed);
      println(line)
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
      recordFail(child, "group threw an unexpected exception");
      False
    }
  };

  groupEpilogue(s, name, passedStart, failedStart, prevExpanded, start)
}

// ─── Assertions ───────────────────────────────────────────────────────────────

/** Equality assertion using `==` (semantic / deep equality; same notion as the VM comparison for structured values). On failure, prints labelled lines so boolean, Int, Unit, String, etc. stay distinguishable via the runtime value printer. */
export fun eq(s: Suite, desc: String, actual: X, expected: X): Unit =
  if (actual == expected)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  expected (right): ${Stk.format(expected)}");
    println("${indent(s.depth)}  actual (left):   ${Stk.format(actual)}");
    println("${indent(s.depth)}  (deep equality / same value shape)")
  }

export fun neq(s: Suite, desc: String, actual: X, notExpected: X): Unit =
  if (actual != notExpected)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  expected: values must differ (deep inequality)");
    println("${indent(s.depth)}  both sides: ${Stk.format(actual)}")
  }

export fun isTrue(s: Suite, desc: String, value: Bool): Unit =
  if (value)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  expected (Bool): true");
    println("${indent(s.depth)}  actual (Bool):   ${Stk.format(value)}")
  }

export fun isFalse(s: Suite, desc: String, value: Bool): Unit =
  if (!value)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  expected (Bool): false");
    println("${indent(s.depth)}  actual (Bool):   ${Stk.format(value)}")
  }

export fun gt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left > right)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  need: left > right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun lt(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left < right)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  need: left < right (strict total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun gte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left >= right)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  need: left >= right (total order on Int)");
    println("${indent(s.depth)}  left (Int):  ${Stk.format(left)}");
    println("${indent(s.depth)}  right (Int): ${Stk.format(right)}")
  }

export fun lte(s: Suite, desc: String, left: Int, right: Int): Unit =
  if (left <= right)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
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
  if (threw)
    recordPass(s, desc)
  else {
    recordFail(s, desc);
    println("${indent(s.depth)}  expected: callee throws an exception");
    println("${indent(s.depth)}  actual:   completed normally (no exception)")
  }
}

export fun printSummary(root: Suite): Unit = {
  val counts = root.counts;
  val p = counts.passed;
  val f = counts.failed;
  val totalElapsed = Basics.nowMs() - counts.startTime;
  // Ignore inherited parent-process tasks when running in-process via CLI delegation.
  val leaked = asyncTasksInFlight() - _asyncInFlightBaseline;
  val leakedSuffix =
    if (leaked > 0) " ${_yel}(${leaked} async task(s) still in flight)${_rst}"
    else "";
  println("");
  if (f > 0) {
    println("${_red}${f} failed${_rst}, ${p} passed (${totalElapsed}ms)${leakedSuffix}");
    exit(1)
  } else {
    println("${_grn}${p} passed${_rst} (${totalElapsed}ms)${leakedSuffix}")
  }
}
