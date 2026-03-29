import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "harness output shape", (s1: Suite) => {
    group(s1, "nested compact smoke", (s2: Suite) => {
      eq(s2, "nested ok", 1, 1)
    });
    eq(s1, "outer ok", 2, 2)
  })
