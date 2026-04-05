import { Suite, group, eq } from "kestrel:tools/test"

export async fun run(s: Suite): Task<Unit> =
  group(s, "arithmetic", (s1: Suite) => {
    eq(s1, "2 + 3 == 5", 2 + 3, 5)
    eq(s1, "10 - 4 == 6", 10 - 4, 6)
    eq(s1, "3 * 7 == 21", 3 * 7, 21)
    eq(s1, "20 / 4 == 5", 20 / 4, 5)
    eq(s1, "17 % 5 == 2", 17 % 5, 2)
    eq(s1, "2 ** 10 == 1024", 2 ** 10, 1024)

    group(s1, "right-assoc and edge cases", (ra: Suite) => {
      eq(ra, "2 ** 3 ** 2 == 512", 2 ** 3 ** 2, 512)
      eq(ra, "3 - 5 negative", 3 - 5, -2)
      eq(ra, "multiply by 1", 7 * 1, 7)
      eq(ra, "divide by 1", 8 / 1, 8)
    })

    group(s1, "precedence and chain", (pc: Suite) => {
      eq(pc, "2+3*4", 2 + 3 * 4, 14)
      eq(pc, "(2+3)*4", (2 + 3) * 4, 20)
      eq(pc, "100/10/2", 100 / 10 / 2, 5)
      eq(pc, "10-3-2", 10 - 3 - 2, 5)
      eq(pc, "10+5", 10 + 5, 15)
      eq(pc, "6*7", 6 * 7, 42)
      eq(pc, "20/4", 20 / 4, 5)
      eq(pc, "17%5", 17 % 5, 2)
    })
  })
