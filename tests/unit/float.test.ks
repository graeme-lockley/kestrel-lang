import { Suite, group, eq, isTrue } from "kestrel:tools/test"

export async fun run(s: Suite): Task<Unit> =
  group(s, "float", (s1: Suite) => {
    group(s1, "literals", (sg: Suite) => {
      eq(sg, "1.0", 1.0, 1.0)
      eq(sg, "0.5", 0.5, 0.5)
      eq(sg, "3.14159", 3.14159, 3.14159)
      eq(sg, "zero", 0.0, 0.0)
      eq(sg, "e-notation 1e2", 1e2, 100.0)
      eq(sg, "e-notation 1.5e1", 1.5e1, 15.0)
      eq(sg, "e-notation 2e-1", 2e-1, 0.2)
    })

    group(s1, "arithmetic", (sg: Suite) => {
      eq(sg, "1.5 + 2.5 == 4.0", 1.5 + 2.5, 4.0)
      eq(sg, "5.0 - 2.0 == 3.0", 5.0 - 2.0, 3.0)
      eq(sg, "2.0 * 3.0 == 6.0", 2.0 * 3.0, 6.0)
      eq(sg, "6.0 / 2.0 == 3.0", 6.0 / 2.0, 3.0)
      eq(sg, "2.0 ** 3.0 == 8.0", 2.0 ** 3.0, 8.0)
    })

    group(s1, "comparison", (sg: Suite) => {
      isTrue(sg, "1.5 == 1.5", 1.5 == 1.5)
      isTrue(sg, "1.5 != 2.5", 1.5 != 2.5)
      isTrue(sg, "1.0 < 2.0", 1.0 < 2.0)
      isTrue(sg, "3.0 > 2.0", 3.0 > 2.0)
      isTrue(sg, "2.0 <= 2.0", 2.0 <= 2.0)
      isTrue(sg, "2.0 >= 2.0", 2.0 >= 2.0)
    })
  })
