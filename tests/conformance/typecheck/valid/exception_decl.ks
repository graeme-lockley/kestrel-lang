// Exception declaration typing: bare and field exceptions, throw, try/catch.
exception SimpleError

exception MyError { message: String }

fun raiseSimple(): Int = throw SimpleError

fun raiseField(): Int = throw MyError("bad input")

fun handled(): Int =
  try { raiseField() } catch { MyError(m) => 0 }
