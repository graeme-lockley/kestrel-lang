import { Suite, group, eq, isTrue, isFalse } from "kestrel:test"

export async fun run(s: Suite): Task<Unit> =
  group(s, "literals", (s1: Suite) => {
    group(s1, "integers", (sg: Suite) => {
      eq(sg, "zero", 0, 0)
      eq(sg, "small positive", 42, 42)
      eq(sg, "large", 1000000, 1000000)
    })
    group(s1, "booleans", (sg: Suite) => {
      isTrue(sg, "True", True)
      isFalse(sg, "False", False)
    })
    group(s1, "strings", (sg: Suite) => {
      eq(sg, "basic literal", "hello", "hello")
      eq(sg, "empty string", "", "")
    })
    group(s1, "unit", (sg: Suite) => {
      eq(sg, "unit value", (), ())
    })
  })
