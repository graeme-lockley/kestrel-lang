import { Suite, group, eq } from "kestrel:tools/test"

export async fun run(s: Suite): Task<Unit> =
  group(s, "harness output shape", (s1: Suite) => {
    group(s1, "nested compact smoke", (s2: Suite) => {
      eq(s2, "nested ok", 1, 1)
    });
    eq(s1, "outer ok", 2, 2)
  })
