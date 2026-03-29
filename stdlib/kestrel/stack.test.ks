import { Suite, group, eq, gt } from "kestrel:test"
import { format, print } from "kestrel:stack"

export fun run(s: Suite): Unit =
  group(s, "stack", (s1: Suite) => {
    group(s1, "format primitives", (sg: Suite) => {
      gt(sg, "Int non-empty", __string_length(format(42)), 0);
      gt(sg, "String non-empty", __string_length(format("hi")), 0);
      gt(sg, "Bool non-empty", __string_length(format(True)), 0);
      gt(sg, "Unit non-empty", __string_length(format(())), 0);
    });

    group(s1, "format composite", (sg: Suite) => {
      val fs = format([1, 2]);
      gt(sg, "List non-empty", __string_length(fs), 0);
    });

    group(s1, "print smoke", (sg: Suite) => {
      print(7);
      print("smoke");
      eq(sg, "no throw", True, True);
    });
  })
