import { Suite, group, eq } from "kestrel:test"
import { length, slice, indexOf, equals, toUpperCase } from "kestrel:string"

export fun run(s: Suite): Unit =
  group(s, "string", (s1: Suite) => {
    group(s1, "length", (sg: Suite) => {
      eq(sg, "empty", length(""), 0);
      eq(sg, "short", length("hi"), 2);
      eq(sg, "multi-word", length("hello world"), 11);
      ()
    });
    group(s1, "slice", (sg: Suite) => {
      eq(sg, "beginning", slice("hello", 0, 2), "he");
      eq(sg, "middle", slice("hello", 1, 4), "ell");
      eq(sg, "full", slice("ab", 0, 2), "ab");
      eq(sg, "empty slice", slice("x", 1, 1), "");
      ()
    });
    group(s1, "indexOf", (sg: Suite) => {
      eq(sg, "found", indexOf("hello", "ll"), 2);
      eq(sg, "not found", indexOf("hello", "z"), 0 - 1);
      eq(sg, "at start", indexOf("hello", "he"), 0);
      ()
    });
    group(s1, "equals", (sg: Suite) => {
      eq(sg, "same", equals("a", "a"), True);
      eq(sg, "different", equals("a", "b"), False);
      eq(sg, "empty", equals("", ""), True);
      ()
    });
    group(s1, "toUpperCase", (sg: Suite) => {
      eq(sg, "lowercase", toUpperCase("hello"), "HELLO");
      eq(sg, "mixed", toUpperCase("HeLLo"), "HELLO");
      eq(sg, "empty", toUpperCase(""), "");
      ()
    });
    ()
  })
