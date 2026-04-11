import { Suite, group, eq, gt, isTrue } from "kestrel:dev/test"
import { format, print, trace } from "kestrel:dev/stack"
import { ArithmeticOverflow } from "kestrel:sys/runtime"
import { length, indexOf } from "kestrel:data/string"

fun throwDeep(): Unit = throw ArithmeticOverflow
fun callDeep(): Unit = throwDeep()

export async fun run(s: Suite): Task<Unit> =
  group(s, "stack", (s1: Suite) => {
    group(s1, "format primitives", (sg: Suite) => {
      gt(sg, "Int non-empty", length(format(42)), 0);
      gt(sg, "String non-empty", length(format("hi")), 0);
      gt(sg, "Bool non-empty", length(format(True)), 0);
      gt(sg, "Unit non-empty", length(format(())), 0);
    });

    group(s1, "format composite", (sg: Suite) => {
      val fs = format([1, 2]);
      gt(sg, "List non-empty", length(fs), 0);
    });

    group(s1, "print smoke", (sg: Suite) => {
      print("");
      isTrue(sg, "no throw", True);
    });

    group(s1, "trace", (sg: Suite) => {
      try {
        callDeep();
        isTrue(sg, "callDeep should throw", False)
      } catch {
        e => {
          val msg = format(trace(e))
          gt(sg, "formatted trace lists frames (at lines)", indexOf(msg, "  at "), -1);
          gt(sg, "formatted trace includes exception", indexOf(msg, "ArithmeticOverflow"), -1);
        }
      }
    });
  })
