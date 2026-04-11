// VM integer overflow and division-by-zero throw catchable exceptions (01 §2.6, 05 §1, 05 §5).
// Canonical types: `kestrel:runtime` (stdlib).
import { Suite, group, eq } from "kestrel:dev/test"
import { ArithmeticOverflow, DivideByZero } from "kestrel:sys/runtime"

// 2^62; two of these sum to 2^63 which exceeds 64-bit signed max (2^63 - 1)
val halfMax = 4611686018427387904

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:lang/overflow", (s1: Suite) => {
    group(s1, "integer overflow", (sg: Suite) => {
      eq(sg, "ADD overflow throws ArithmeticOverflow",
        try { halfMax + halfMax } catch { ArithmeticOverflow => 1, other => 0 }, 1)
      eq(sg, "SUB overflow throws ArithmeticOverflow",
        try { -halfMax - halfMax - 1 } catch { ArithmeticOverflow => 1, other => 0 }, 1)
      eq(sg, "MUL overflow throws ArithmeticOverflow",
        try { halfMax * 2 } catch { ArithmeticOverflow => 1, other => 0 }, 1)
    })

    group(s1, "division by zero", (sg: Suite) => {
      eq(sg, "DIV by zero throws DivideByZero",
        try { 1 / 0 } catch { DivideByZero => 1, other => 0 }, 1)
    })

    group(s1, "modulo by zero", (sg: Suite) => {
      eq(sg, "MOD by zero throws DivideByZero",
        try { 1 % 0 } catch { DivideByZero => 1, other => 0 }, 1)
    })
  })
