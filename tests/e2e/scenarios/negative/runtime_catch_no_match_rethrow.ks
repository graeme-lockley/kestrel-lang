// E2E_SKIP_PENDING_CODEGEN: temporary self-hosted main stub does not execute runtime-negative scenarios; re-enable with S17-37 and dependent codegen stories
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
