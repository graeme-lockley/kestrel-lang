// Provenance: tests/conformance/typecheck/valid/exception_decl.ks (baseline S17-19)
// Exception declaration typing: bare and field exceptions, throw, try/catch.
exception SimpleError

exception MyError(message: String)

fun raiseSimple(): Int = throw SimpleError

fun raiseField(): Int = throw MyError("bad input")

fun handled(): Int =
  try { raiseField() } catch (MyError(m)) { m => 0 }
