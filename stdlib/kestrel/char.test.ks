import { Suite, group, eq } from "kestrel:test"
import { codePoint, isDigit } from "kestrel:char"

export fun run(s: Suite): Unit =
  group(s, "char", (s1: Suite) => {
    group(s1, "codePoint", (sg: Suite) => {
      eq(sg, "A", codePoint('A'), 65)
    })

    group(s1, "isDigit", (sg: Suite) => {
      eq(sg, "zero", isDigit('0'), True)
      eq(sg, "nine", isDigit('9'), True)
      eq(sg, "letter", isDigit('a'), False)
      eq(sg, "space", isDigit(' '), False)
    })
  })
