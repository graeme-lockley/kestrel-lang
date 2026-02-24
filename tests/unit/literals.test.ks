import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "literals", (s1: Suite) => {
    group(s1, "integers", (sg: Suite) => {
      eq(sg, "zero", 0, 0)
      eq(sg, "small positive", 42, 42)
      eq(sg, "large", 1000000, 1000000)
    })
    group(s1, "booleans", (sg: Suite) => {
      eq(sg, "True", True, True)
      eq(sg, "False", False, False)
    })
    group(s1, "strings", (sg: Suite) => {
      eq(sg, "basic literal", "hello", "hello")
      eq(sg, "empty string", "", "")
    })
    group(s1, "unit", (sg: Suite) => {
      eq(sg, "unit value", (), ())
    })
  })
