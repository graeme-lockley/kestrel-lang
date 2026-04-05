import { Suite, group, eq, gte, isTrue, isFalse } from "kestrel:tools/test"
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
  isInfinite,
  nowMs
} from "kestrel:data/basics"

export async fun run(s: Suite): Task<Unit> =
  group(s, "basics", (s1: Suite) => {
    group(s1, "time", (sg: Suite) => {
      gte(sg, "nowMs non-negative", nowMs(), 0)
    })

    group(s1, "pure", (sg: Suite) => {
      eq(sg, "identity", identity(7), 7)
      eq(sg, "always", always(1, 2), 1)
      eq(sg, "clamp mid", clamp(0, 10, 5), 5)
      eq(sg, "clamp low", clamp(0, 10, -3), 0)
      eq(sg, "clamp high", clamp(0, 10, 99), 10)
      eq(sg, "negate", negate(4), -4)
      eq(sg, "modBy sign of divisor", modBy(5, -12), 3)
      eq(sg, "remainderBy", remainderBy(5, -12), -2)
      isFalse(sg, "xor ff", xor(False, False))
      isTrue(sg, "xor ft", xor(False, True))
      isTrue(sg, "not", not(False))
    })

    group(s1, "float", (sg: Suite) => {
      eq(sg, "toFloat", truncate(toFloat(42)), 42)
      eq(sg, "floor", floor(toFloat(9) / toFloat(2)), 4)
      eq(sg, "ceiling", ceiling(toFloat(9) / toFloat(2)), 5)
      eq(sg, "round int", round(toFloat(7)), 7)
      eq(sg, "abs neg", abs(toFloat(-3)), toFloat(3))
      eq(sg, "sqrt 4", truncate(sqrt(toFloat(16))), 4)
      isTrue(sg, "isNaN sqrt -1", isNaN(sqrt(toFloat(-1))))
      isFalse(sg, "isFinite not nan", isNaN(toFloat(0)))
    })
  })
