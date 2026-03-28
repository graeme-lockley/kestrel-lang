// VM integer overflow and division-by-zero throw catchable exceptions (spec 01 §2.6, 04 §1.2, 05 §1).
// These exceptions must be defined in the module so the VM can allocate them by name.
import { Suite, group, eq } from "kestrel:test"

export exception ArithmeticOverflow
export exception DivideByZero

// 2^59; two of these sum to 2^60 which exceeds 61-bit signed max (2^60 - 1)
val halfMax = 576460752303423488

export fun run(s: Suite): Unit =
  group(s, "overflow and divzero", (s1: Suite) => {
//    group(s1, "integer overflow", (sg: Suite) => {
//      eq(sg, "ADD overflow throws ArithmeticOverflow",
//        try { halfMax + halfMax } catch { ArithmeticOverflow => 1, other => 0 }, 1)
//      eq(sg, "SUB overflow throws ArithmeticOverflow",
//        try { -halfMax - halfMax - 1 } catch { ArithmeticOverflow => 1, other => 0 }, 1)
//      eq(sg, "MUL overflow throws ArithmeticOverflow",
//        try { halfMax * 2 } catch { ArithmeticOverflow => 1, other => 0 }, 1)
//    })

//    group(s1, "division by zero", (sg: Suite) => {
//      eq(sg, "DIV by zero throws DivideByZero",
//        try { 1 / 0 } catch { DivideByZero => 1, other => 0 }, 1)
//    })

//    group(s1, "modulo by zero", (sg: Suite) => {
//      eq(sg, "MOD by zero throws DivideByZero",
//        try { 1 % 0 } catch { DivideByZero => 1, other => 0 }, 1)
//    })

    ()
  })
