import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "tuples", (s1: Suite) => {
    val pair = (10, 20);
    eq(s1, "pair.0", "${pair.0}", "${10}");
    eq(s1, "pair.1", "${pair.1}", "${20}");
    eq(s1, "inline .0", "${(100, 200, 300).0}", "${100}");
    eq(s1, "inline .1", "${(100, 200, 300).1}", "${200}");
    eq(s1, "inline .2", "${(100, 200, 300).2}", "${300}");
    group(s1, "nested", (n: Suite) => {
      val nested = ((1, 2), (3, 4));
      eq(n, "nested.0.0", "${nested.0.0}", "${1}");
      eq(n, "nested.0.1", "${nested.0.1}", "${2}");
      eq(n, "nested.1.0", "${nested.1.0}", "${3}");
      eq(n, "nested.1.1", "${nested.1.1}", "${4}");
      ()
    });
    ()
  })
