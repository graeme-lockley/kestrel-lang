import { Suite, group, eq } from "kestrel:test"
import { length, isEmpty } from "kestrel:list"

export fun run(s: Suite): Unit =
  group(s, "list", (s1: Suite) => {
    group(s1, "length", (sg: Suite) => {
      eq(sg, "empty", length([]), 0);
      eq(sg, "singleton", length([1]), 1);
      eq(sg, "multi-element", length([1, 2, 3]), 3);
      ()
    });
    group(s1, "isEmpty", (sg: Suite) => {
      eq(sg, "empty", isEmpty([]), True);
      eq(sg, "non-empty", isEmpty([1, 2, 3]), False);
      eq(sg, "singleton", isEmpty([42]), False);
      ()
    });
    ()
  })
