import { Suite, group, eq } from "kestrel:test"
import {
  identity,
  always,
  clamp,
  negate,
  modBy,
  remainderBy,
  xor,
  not,
  toFloat,
  truncate,
  floor,
  ceiling,
  round,
  abs,
  sqrt,
  isNaN,
  isInfinite
} from "kestrel:basics"

export fun run(s: Suite): Unit =
  group(s, "basics", (s1: Suite) => {
    group(s1, "pure", (sg: Suite) => {
      eq(sg, "identity", identity(7), 7)
      eq(sg, "always", always(1, 2), 1)
      eq(sg, "clamp mid", clamp(0, 10, 5), 5)
      eq(sg, "clamp low", clamp(0, 10, -3), 0)
      eq(sg, "clamp high", clamp(0, 10, 99), 10)
      eq(sg, "negate", negate(4), 0 - 4)
      eq(sg, "modBy sign of divisor", modBy(5, -12), 3)
      eq(sg, "remainderBy", remainderBy(5, -12), -2)
      eq(sg, "xor ff", xor(False, False), False)
      eq(sg, "xor ft", xor(False, True), True)
      eq(sg, "not", not(False), True)
    })

    group(s1, "float", (sg: Suite) => {
      eq(sg, "toFloat", truncate(toFloat(42)), 42)
      eq(sg, "floor", floor(toFloat(9) / toFloat(2)), 4)
      eq(sg, "ceiling", ceiling(toFloat(9) / toFloat(2)), 5)
      eq(sg, "round int", round(toFloat(7)), 7)
      eq(sg, "abs neg", abs(toFloat(0 - 3)), toFloat(3))
      eq(sg, "sqrt 4", truncate(sqrt(toFloat(16))), 4)
      eq(sg, "isNaN sqrt -1", isNaN(sqrt(toFloat(0 - 1))), True)
      eq(sg, "isFinite not nan", isNaN(toFloat(0)), False)
    })
  })
