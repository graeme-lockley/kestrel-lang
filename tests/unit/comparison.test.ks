import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "comparison", (s1: Suite) => {
    group(s1, "equality", (sg: Suite) => {
      eq(sg, "5 == 5", 5 == 5, True)
      eq(sg, "5 == 3 is false", 5 == 3, False)
      eq(sg, "0 == 0", 0 == 0, True)
    })
    group(s1, "inequality", (sg: Suite) => {
      eq(sg, "5 != 3", 5 != 3, True)
      eq(sg, "5 != 5 is false", 5 != 5, False)
    })
    group(s1, "less than", (sg: Suite) => {
      eq(sg, "3 < 5", 3 < 5, True)
      eq(sg, "5 < 3 is false", 5 < 3, False)
      eq(sg, "-1 < 0", 0 - 1 < 0, True)
    })
    group(s1, "greater than", (sg: Suite) => {
      eq(sg, "7 > 4", 7 > 4, True)
      eq(sg, "4 > 7 is false", 4 > 7, False)
    })
    group(s1, "less or equal", (sg: Suite) => {
      eq(sg, "3 <= 3", 3 <= 3, True)
      eq(sg, "3 <= 5", 3 <= 5, True)
      eq(sg, "4 <= 3 is false", 4 <= 3, False)
    })
    group(s1, "greater or equal", (sg: Suite) => {
      eq(sg, "5 >= 5", 5 >= 5, True)
      eq(sg, "7 >= 4", 7 >= 4, True)
      eq(sg, "4 >= 5 is false", 4 >= 5, False)
    })
  })
