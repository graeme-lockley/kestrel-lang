import { Suite, group, eq } from "kestrel:test"

fun boolToStr(b: Bool): String = if (b) "true" else "false"

fun classify(n: Int): Int =
  if (n < 0) 0
  else if (n == 0) 1
  else 2

fun boolToInt(b: Bool): Int = match (b) { True => 1, False => 0 }

fun boolToString(b: Bool): String = match (b) { False => "False", True => "True" }

export fun run(s: Suite): Unit =
  group(s, "control flow", (s1: Suite) => {
    group(s1, "if/else", (ie: Suite) => {
      eq(ie, "true branch", "${if (True) 42 else 0}", "${42}");
      eq(ie, "false branch", "${if (False) 0 else 99}", "${99}");
      eq(ie, "nested classify(-5)", "${classify(0 - 5)}", "${0}");
      eq(ie, "nested classify(0)", "${classify(0)}", "${1}");
      eq(ie, "nested classify(10)", "${classify(10)}", "${2}");
      ()
    });

    group(s1, "comparison", (cmp: Suite) => {
      eq(cmp, "5 == 5", boolToStr(5 == 5), "true");
      eq(cmp, "5 != 3", boolToStr(5 != 3), "true");
      eq(cmp, "3 < 5", boolToStr(3 < 5), "true");
      eq(cmp, "7 > 4", boolToStr(7 > 4), "true");
      eq(cmp, "3 <= 3", boolToStr(3 <= 3), "true");
      eq(cmp, "4 >= 5 is false", boolToStr(4 >= 5), "false");
      ()
    });

    group(s1, "boolean operators", (bo: Suite) => {
      eq(bo, "True & True", boolToStr(True & True), "true");
      eq(bo, "True & False", boolToStr(True & False), "false");
      eq(bo, "False & True", boolToStr(False & True), "false");
      eq(bo, "True | False", boolToStr(True | False), "true");
      eq(bo, "False | False", boolToStr(False | False), "false");
      eq(bo, "!True", boolToStr(!True), "false");
      eq(bo, "!False", boolToStr(!False), "true");
      ()
    });

    group(s1, "pattern boolean", (pb: Suite) => {
      eq(pb, "boolToInt(True)", "${boolToInt(True)}", "${1}");
      eq(pb, "boolToInt(False)", "${boolToInt(False)}", "${0}");
      eq(pb, "boolToString(True)", boolToString(True), "True");
      eq(pb, "boolToString(False)", boolToString(False), "False");
      eq(pb, "match True => 10", "${match (True) { True => 10, False => 20 }}", "${10}");
      eq(pb, "match False => 40", "${match (False) { True => 30, False => 40 }}", "${40}");
      ()
    });

    group(s1, "unary with boolean", (uw: Suite) => {
      eq(uw, "!(3>5)&(2<4)", boolToStr(!(3 > 5) & (2 < 4)), "true");
      eq(uw, "if (!(False|False)) -100 else -200", "${if (!(False | False)) (0 - 100) else (0 - 200)}", "${-100}");
      ()
    });
    ()
  })
