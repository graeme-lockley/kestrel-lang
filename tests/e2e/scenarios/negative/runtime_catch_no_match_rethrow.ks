// E2E_EXPECT_STACK_TRACE
// Expected phase: runtime — catch has no arm for thrown value (01 §4); rethrows and terminates.
// Substitute for “unexpected ADT constructor” bucket: discriminant mismatch in catch patterns.

import { DivideByZero, ArithmeticOverflow } from "kestrel:sys/runtime"

fun run(): Unit =
  try {
    throw(DivideByZero)
  } catch (e) {
    ArithmeticOverflow => ()
  }

run()
