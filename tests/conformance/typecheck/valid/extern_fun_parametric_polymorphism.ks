// Regression test: parametric extern fun must generalize its type param properly
// even when other functions are defined before/after it in the same module.
// Previously, ExternFunDecl did not call env.delete(name) before envFreeVars(),
// so the type param variable was seen as "in scope" and not generalized.

extern fun fmt<A>(x: A): String = jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")

fun useString(s: String): String = s
fun useBool(b: Bool): Bool = b

// After helper functions are processed, fmt<A> must still be polymorphic:
// it must accept both String and Bool without locking in A to a single type.
// Both calls must type-check without error: A is instantiated independently each time
fun checkStr(s: String): String = s
fun checkBool(s: String): String = s
val s = checkStr(fmt("hello"))
val b = checkBool(fmt(True))
