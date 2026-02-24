import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "logical", (s1: Suite) => {
    group(s1, "and", (sg: Suite) => {
      eq(sg, "True & True", True & True, True);
      eq(sg, "True & False", True & False, False);
      eq(sg, "False & True", False & True, False);
      eq(sg, "False & False", False & False, False);
      ()
    });
    group(s1, "or", (sg: Suite) => {
      eq(sg, "True | False", True | False, True);
      eq(sg, "False | True", False | True, True);
      eq(sg, "False | False", False | False, False);
      eq(sg, "True | True", True | True, True);
      ()
    });
    group(s1, "not", (sg: Suite) => {
      eq(sg, "!True", !True, False);
      eq(sg, "!False", !False, True);
      ()
    });
    group(s1, "compound", (sg: Suite) => {
      eq(sg, "!(3>5)&(2<4)", !(3 > 5) & (2 < 4), True);
      eq(sg, "(True|False)&(False|True)", (True | False) & (False | True), True);
      eq(sg, "if (!(False|False)) -100 else -200", if (!(False | False)) (0 - 100) else (0 - 200), 0 - 100);
      ()
    });
    group(s1, "short circuit and", (sg: Suite) => {
      eq(sg, "False & True yields False", False & True, False);
      eq(sg, "False & False yields False", False & False, False);
      ()
    });
    group(s1, "short circuit or", (sg: Suite) => {
      eq(sg, "True | False yields True", True | False, True);
      eq(sg, "True | True yields True", True | True, True);
      ()
    });
    ()
  })
